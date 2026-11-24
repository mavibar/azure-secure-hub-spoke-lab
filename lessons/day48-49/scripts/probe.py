"""Runs only inside the disposable VM. Prints no token or blob body."""
import datetime, http.client, json, socket, ssl, sys, urllib.request
import xml.etree.ElementTree as ET

cfg = json.loads(sys.argv[1])
host = cfg['storage'] + '.blob.core.windows.net'
private = cfg['private_ip']
resolved = sorted({v[4][0] for v in socket.getaddrinfo(host, 443, socket.AF_INET)})
if resolved != [private]:
    raise SystemExit('DNS did not resolve exclusively to the saved private endpoint.')
request = urllib.request.Request(
    'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F',
    headers={'Metadata': 'true'})
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
with opener.open(request, timeout=15) as response:
    token = json.load(response)['access_token']

class PinnedConnection(http.client.HTTPSConnection):
    def __init__(self, ip):
        super().__init__(host, timeout=20, context=ssl.create_default_context())
        self.target_ip = ip
    def connect(self):
        # Connect to a selected address, retaining normal hostname/SNI and TLS verification.
        self.sock = self._context.wrap_socket(
            socket.create_connection((self.target_ip, 443), self.timeout), server_hostname=host)

def probe(ip, method='GET'):
    conn = PinnedConnection(ip)
    headers = {'Authorization': 'Bearer ' + token, 'x-ms-version': '2023-11-03'}
    data = None
    if method == 'PUT':
        headers['x-ms-blob-type'] = 'BlockBlob'
        data = b'Cloud Security Lab dummy data. No production information.\n'
    conn.request(method, '/lesson/dummy.txt', body=data, headers=headers)
    response = conn.getresponse()
    body = response.read()
    code = None
    if response.status >= 400:
        try:
            code = ET.fromstring(body).findtext('Code')
        except ET.ParseError:
            code = 'NonXmlError'
    result = {'status': response.status, 'error_code': code,
              'request_id': response.getheader('x-ms-request-id'),
              'date': response.getheader('Date'), 'destination_ip': ip}
    conn.close()
    return result

result = {'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'dns': resolved, 'origin': 'Private VNet VM managed identity', 'tls_verified': True}
if cfg.get('seed'):
    result['seed'] = probe(private, 'PUT')
    if result['seed']['status'] != 201:
        print('CSL_RESULT=' + json.dumps(result)); raise SystemExit(2)
result['private'] = probe(private)
result['pass'] = result['private']['status'] == 200
print('CSL_RESULT=' + json.dumps(result))
raise SystemExit(0 if result['pass'] else 2)
