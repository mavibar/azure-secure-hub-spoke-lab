"""Runs only inside the disposable execution VM. Raw material stays private."""
import base64, hashlib, json, os, pathlib, re, subprocess, sys

ADDRESS = 'azurerm_network_security_group.proposed'
stage = 'input'
def review(document, expected, revision, expected_rg=None):
    rows = []
    for item in document.get('resource_changes', []):
        if item.get('mode') == 'data' and item.get('address') == 'data.azurerm_resource_group.lab' and item.get('change',{}).get('actions') in (['read'],['no-op']):
            continue
        actions = item.get('change', {}).get('actions')
        if item.get('mode') != 'managed' or item.get('address') != ADDRESS or actions != [expected]:
            raise ValueError('Unexpected resource change')
        change=item['change']
        target=change.get('before') if expected=='delete' else change.get('after')
        if not target or target.get('name')!='nsg-csl-ci-review':
            raise ValueError('Unexpected target name')
        for value in (change.get('before'),change.get('after')):
            if value and (value.get('name')!='nsg-csl-ci-review' or (expected_rg is not None and value.get('resource_group_name')!=expected_rg)):
                raise ValueError('Unexpected existing or desired resource scope')
        if expected != 'delete':
            after = item['change'].get('after') or {}
            if after.get('name') != 'nsg-csl-ci-review' or after.get('tags') != {'purpose':'learning','revision':revision}:
                raise ValueError('Unexpected desired configuration')
            if after.get('security_rule') not in (None, []):
                raise ValueError('Custom rule outside exercise')
        rows.append(item)
    if len(rows) != 1 or document.get('output_changes') or document.get('errored'):
        raise ValueError('Expected exactly one reviewed change')
    return {'address':ADDRESS,'action':expected,'revision':revision}

def main(job):
    global stage
    os.umask(0o077)
    if not re.fullmatch(r'\d+-\d+', job['run_key']) or not re.fullmatch(r'[0-9a-f]{40}',job['commit']):
        raise ValueError('Invalid execution identity')
    if job['revision'] not in ('v1','v2') or job['expected'] not in ('create','update','delete') or job['phase'] not in ('plan','apply'):
        raise ValueError('Invalid operation')
    root = pathlib.Path('/var/lib/csl-lab') / job['run_key'] / job['phase']
    root.mkdir(parents=True, exist_ok=False)  # No ambiguous apply retries.
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(('TF_', 'ARM_', 'AZURE_STORAGE_')): env.pop(key)
    env.update(AZURE_CONFIG_DIR=str(root/'az'),AZURE_CORE_OUTPUT='none',
        ARM_CLIENT_ID=job['client'],ARM_TENANT_ID=job['tenant'],ARM_SUBSCRIPTION_ID=job['subscription'],
        ARM_USE_MSI='true',ARM_USE_AZUREAD='true',ARM_USE_CLI='false',ARM_USE_OIDC='false',
        TF_IN_AUTOMATION='true',CHECKPOINT_DISABLE='1',TF_VAR_lab_resource_group=job['lab_rg'],TF_VAR_revision=job['revision'])
    def run(args,label,accepted=(0,)):
        global stage
        stage=label
        out=root/(label+'.out'); err=root/(label+'.err')
        with out.open('wb') as stdout,err.open('wb') as stderr:
            code=subprocess.run(args,env=env,stdout=stdout,stderr=stderr,timeout=480,check=False).returncode
        if code not in accepted: raise ValueError('Command failed')
        return code,out
    run(['az','login','--identity','--client-id',job['client'],'--output','none'],'login')
    _,out=run(['az','account','show','-o','json'],'account')
    acct=json.loads(out.read_text())
    if acct.get('id','').lower()!=job['subscription'].lower() or acct.get('tenantId','').lower()!=job['tenant'].lower(): raise ValueError('Context mismatch')
    for name in ('main.tf','.terraform.lock.hcl'):
        (root/name).write_bytes(base64.b64decode(job['files'][name],validate=True))
    config={'storage_account_name':job['storage'],'container_name':job['container'],'key':'day42-43.tfstate',
        'use_msi':True,'use_azuread_auth':True,'use_cli':False,'use_oidc':False,'client_id':job['client'],
        'tenant_id':job['tenant'],'subscription_id':job['subscription'],'lookup_blob_endpoint':False}
    backend=root/'backend.hcl'
    backend.write_text(''.join(k+' = '+json.dumps(v)+'\n' for k,v in config.items()))
    tf=['terraform','-chdir='+str(root)]
    run(tf+['init','-input=false','-no-color','-lockfile=readonly','-backend-config='+str(backend)],'init')
    run(tf+['validate','-no-color'],'validate')
    state_code,listing=run(tf+['state','list'],'state-list',(0,1))
    if state_code and 'No state file was found' not in (root/'state-list.err').read_text():
        raise ValueError('State inventory failed')
    addresses=[x.strip() for x in listing.read_text().splitlines() if x.strip()]
    if any(x not in (ADDRESS,'data.azurerm_resource_group.lab') for x in addresses): raise ValueError('Unexpected existing state')
    plan=root/'review.tfplan'; blob='plans/'+job['run_key']+'/review.tfplan'
    storage=['--account-name',job['storage'],'--container-name',job['container'],'--auth-mode','login','--only-show-errors']
    if job['phase']=='plan':
        args=tf+['plan','-input=false','-no-color','-detailed-exitcode','-lock-timeout=30s','-out='+str(plan)]
        if job['expected']=='delete': args.append('-destroy')
        run(args,'plan',(2,))
        _,raw=run(tf+['show','-json',str(plan)],'show')
        safe=review(json.loads(raw.read_text()),job['expected'],job['revision'],job['lab_rg'])
        digest=hashlib.sha256(plan.read_bytes()).hexdigest()
        run(['az','storage','blob','upload',*storage,'--name',blob,'--file',str(plan),'--overwrite','false','-o','none'],'save-plan')
    else:
        if not re.fullmatch(r'[0-9a-f]{64}',job['digest']): raise ValueError('Invalid approved digest')
        run(['az','storage','blob','download',*storage,'--name',blob,'--file',str(plan),'-o','none'],'load-plan')
        digest=hashlib.sha256(plan.read_bytes()).hexdigest()
        if digest!=job['digest']: raise ValueError('Plan digest mismatch')
        _,raw=run(tf+['show','-json',str(plan)],'show')
        safe=review(json.loads(raw.read_text()),job['expected'],job['revision'],job['lab_rg'])
        (root/'apply-started').write_text(digest)
        run(tf+['apply','-input=false','-no-color',str(plan)],'apply')
        verify=tf+['plan','-input=false','-no-color','-detailed-exitcode','-lock-timeout=30s']
        if job['expected']=='delete': verify.append('-destroy')
        run(verify,'post-plan',(0,))
        run(['az','storage','blob','delete',*storage,'--name',blob,'--delete-snapshots','include','-o','none'],'remove-plan')
        (root/'apply-completed').write_text(digest)
    _,lease=run(['az','storage','blob','show',*storage,'--name','day42-43.tfstate','-o','json'],'lease')
    if json.loads(lease.read_text()).get('properties',{}).get('lease',{}).get('status')!='unlocked': raise ValueError('Lease not unlocked')
    safe.update(status='PASS',phase=job['phase'],digest=digest,run_key=job['run_key'],commit=job['commit'],lease='unlocked')
    print('CSL_RESULT='+base64.b64encode(json.dumps(safe).encode()).decode())

if __name__=='__main__':
    try: main(json.loads(pathlib.Path(sys.argv[1]).read_text()))
    except Exception:
        print('CSL_RESULT='+base64.b64encode(json.dumps({'status':'FAIL','stage':stage}).encode()).decode())
        sys.exit(1)
