"""GitHub controls one exact VM; it never handles the raw binary plan."""
import base64,json,os,pathlib,re,subprocess,sys,tempfile
def main():
    e=os.environ; base=pathlib.Path(__file__).resolve().parents[1]
    phase=e['PHASE']; run_key=e.get('PLAN_RUN_KEY') if phase=='apply' else e['GITHUB_RUN_ID']+'-'+e['GITHUB_RUN_ATTEMPT']
    names=('AZURE_CLIENT_ID','AZURE_TENANT_ID','AZURE_SUBSCRIPTION_ID','EXEC_RG','EXEC_VM','LAB_RESOURCE_GROUP','TFSTATE_STORAGE_ACCOUNT','TFSTATE_CONTAINER')
    if not all(e.get(n) for n in names): raise ValueError('Missing environment configuration')
    job={'phase':phase,'run_key':run_key,'commit':e['GITHUB_SHA'],'revision':(base/'revision.txt').read_text().strip(),
        'expected':e['EXPECTED_ACTION'],'client':e['AZURE_CLIENT_ID'],'tenant':e['AZURE_TENANT_ID'],
        'subscription':e['AZURE_SUBSCRIPTION_ID'],'lab_rg':e['LAB_RESOURCE_GROUP'],
        'storage':e['TFSTATE_STORAGE_ACCOUNT'],'container':e['TFSTATE_CONTAINER'],'digest':e.get('PLAN_DIGEST',''),
        'files':{n:base64.b64encode((base/'terraform'/n).read_bytes()).decode() for n in ('main.tf','.terraform.lock.hcl')}}
    payload=base64.b64encode(json.dumps(job).encode()).decode()
    engine=base64.b64encode((base/'scripts/guest.py').read_bytes()).decode()
    # mktemp avoids interpolating resource names or caller inputs into shell code.
    script="set -eu\numask 077\nd=$(mktemp -d /var/tmp/csl-dispatch.XXXXXX)\ntrap 'rm -rf -- \"$d\"' EXIT\n"
    script+="printf '%s' '"+payload+"' | base64 -d > \"$d/job.json\"\n"
    script+="printf '%s' '"+engine+"' | base64 -d > \"$d/guest.py\"\n"
    script+='cloud-init status --wait >/dev/null 2>&1\npython3 "$d/guest.py" "$d/job.json"\n'
    with tempfile.TemporaryDirectory(prefix='csl-dispatch-',dir=e['RUNNER_TEMP']) as folder:
        path=pathlib.Path(folder)/'command.sh'; path.write_text(script)
        result=subprocess.run(['az','vm','run-command','invoke','--resource-group',e['EXEC_RG'],'--name',e['EXEC_VM'],
            '--subscription',e['AZURE_SUBSCRIPTION_ID'],'--command-id','RunShellScript','--scripts','@'+str(path),'-o','json','--only-show-errors'],
            capture_output=True,text=True,timeout=1100)
        if result.returncode: raise ValueError('Run Command API failed')
        body=json.loads(result.stdout)
        messages='\n'.join(v.get('message','') for v in body.get('value',[]))
        matches=re.findall(r'CSL_RESULT=([A-Za-z0-9+/=]+)',messages)
        if len(matches)!=1: raise ValueError('Missing or ambiguous guest result')
        safe=json.loads(base64.b64decode(matches[0],validate=True))
        if safe.get('status')!='PASS':
            stage=safe.get('stage','unknown')
            if not re.fullmatch(r'[a-z-]{1,32}',stage): stage='unknown'
            print('Guest stopped at stage: '+stage)
            raise ValueError('Guest operation failed')
        if safe.get('commit')!=e['GITHUB_SHA'] or safe.get('run_key')!=run_key or not re.fullmatch(r'[0-9a-f]{64}',safe.get('digest','')): raise ValueError('Evidence mismatch')
        print(json.dumps(safe))
        with open(e['GITHUB_OUTPUT'],'a') as f:
            f.write('digest='+safe['digest']+'\nrun_key='+run_key+'\n')
        with open(e['GITHUB_STEP_SUMMARY'],'a') as f:
            f.write('```json\n'+json.dumps(safe,indent=2)+'\n```\n')
if __name__=='__main__':
    try: main()
    except Exception:
        print('Execution did not produce verified success. Inspect the exact VM Run Command and private guest logs; do not blindly retry apply.',file=sys.stderr)
        sys.exit(1)
