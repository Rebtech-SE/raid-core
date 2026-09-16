"""Azure DevOps Services REST primitives. Duplicated in the resolver for skill isolation."""
import base64
import json
import os
import re
import subprocess
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.parse import quote, unquote, urlsplit, urlencode
from urllib.request import Request, HTTPRedirectHandler, build_opener


class EvidenceError(Exception):
    pass


def positive(value):
    if not re.fullmatch(r'[1-9][0-9]*', str(value)):
        raise EvidenceError('Expected a positive integer ID')
    return int(value)


def component(value):
    if not isinstance(value, str) or not value or value in ('.', '..') or any(c in value for c in '/\\\r\n\0'):
        raise EvidenceError('Invalid Azure identity component')
    return value


@dataclass(frozen=True)
class Identity:
    org: str
    project: str
    repository: str
    pr: int

    def __post_init__(self):
        for v in (self.org, self.project, self.repository):
            component(v)
        positive(self.pr)

    @property
    def base(self):
        return 'https://dev.azure.com/' + quote(self.org, safe='') + '/' + quote(self.project, safe='')

    @property
    def url(self):
        return self.base + '/_git/' + quote(self.repository, safe='') + '/pullrequest/' + str(self.pr)

    @property
    def path(self):
        return 'git/repositories/' + quote(self.repository, safe='') + '/pullRequests/' + str(self.pr)

    @property
    def artifact(self):
        # Only call after canonicalizing project to the returned project UUID.
        return f'vstfs:///CodeReview/CodeReviewId/{self.project}/{self.pr}'


def identity(value, pr=None):
    """Full web PR URL, or Services HTTPS/SSH remote plus explicit PR ID; no ambient defaults."""
    if value.startswith('git@ssh.dev.azure.com:v3/'):
        parts = value[len('git@ssh.dev.azure.com:v3/'):].split('/')
        if len(parts) != 3 or pr is None:
            raise EvidenceError('Azure SSH remote requires organization/project/repository and --pr')
        return Identity(*[component(unquote(x)) for x in parts], positive(pr))
    u = urlsplit(value)
    if u.scheme != 'https' or u.password or u.port or u.fragment:
        raise EvidenceError('Use an Azure Services HTTPS PR URL (without fragment), or remote plus --pr')
    parts = [component(unquote(x)) for x in u.path.strip('/').split('/')]
    if u.hostname == 'dev.azure.com':
        org, *parts = parts
    elif u.hostname and re.fullmatch(r'[a-zA-Z0-9-]+\.visualstudio\.com', u.hostname):
        org = u.hostname.split('.')[0]
        if parts[0].lower() == 'defaultcollection':
            parts = parts[1:]
    else:
        raise EvidenceError('Unsupported host: Azure DevOps Services only; Server is not supported')
    if len(parts) not in (3, 5) or parts[1].lower() != '_git':
        raise EvidenceError('Expected an exact Azure project/repository URL')
    if len(parts) == 5:
        if parts[3].lower() != 'pullrequest' or (pr is not None and positive(pr) != positive(parts[4])):
            raise EvidenceError('Conflicting or invalid PR identity')
        pr = parts[4]
    if pr is None:
        raise EvidenceError('Repository URL requires an explicit --pr; a PR number alone is not an identity')
    return Identity(org, parts[0], parts[2], positive(pr))


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise EvidenceError('Azure API redirected; authentication or identity must be checked')


class Client:
    def __init__(self, target):
        self.target = target
        self.authorization = None

    def auth(self):
        if self.authorization is None:
            pat = os.environ.get('AZURE_DEVOPS_EXT_PAT')
            if pat:
                self.authorization = 'Basic ' + base64.b64encode((':' + pat).encode()).decode()
            else:
                result = subprocess.run(['az', 'account', 'get-access-token', '--resource',
                    '499b84ac-1321-427f-aa17-267ca6975798', '--query', 'accessToken', '-o', 'tsv'],
                    capture_output=True, text=True, timeout=45)
                if result.returncode or not result.stdout.strip():
                    raise EvidenceError('Azure authentication unavailable; use an existing az Entra session or supplied AZURE_DEVOPS_EXT_PAT')
                self.authorization = 'Bearer ' + result.stdout.strip()
        return self.authorization

    def request(self, path, query=None, method='GET', body=None, version='7.1'):
        if path.startswith('/') or '..' in path.split('/') or '://' in path:
            raise EvidenceError('Only skill-constructed relative API paths are accepted')
        url = self.target.base + '/_apis/' + path + '?' + urlencode({'api-version': version, **(query or {})})
        req = Request(url, data=None if body is None else json.dumps(body).encode(), method=method,
            headers={'Authorization': self.auth(), 'Accept': 'application/json', 'Content-Type': 'application/json'})
        try:
            with build_opener(NoRedirect()).open(req, timeout=45) as response:
                data = json.load(response)
                return data, response.headers.get('x-ms-continuationtoken')
        except HTTPError as error:
            raise EvidenceError(f'Azure {method} {path}: HTTP {error.code}; required evidence/action unavailable') from None
        except (URLError, ValueError, TimeoutError):
            raise EvidenceError(f'Azure {method} {path}: unreadable response') from None

    def get(self, path, query=None):
        data, token = self.request(path, query)
        if token:
            raise EvidenceError('Unexpected pagination on object response')
        return data

    def collection(self, path, query=None, paging=None, version='7.1'):
        rows, seen = [], set()
        query = dict(query or {})
        if paging:
            query['$top'] = 100
        for _ in range(1000):
            data, token = self.request(path, query, version=version)
            if not isinstance(data, dict) or not isinstance(data.get('value'), list):
                raise EvidenceError(f'{path}: expected a complete collection envelope')
            page = data['value']
            rows.extend(page)
            if paging == 'skip':
                if token:
                    raise EvidenceError('Unexpected continuation token on skip-paged endpoint')
                if len(page) < 100:
                    return rows
                query['$skip'] = len(rows)
            elif token and paging == 'token':
                if token in seen:
                    raise EvidenceError('Repeated continuation token')
                seen.add(token)
                query['continuationToken'] = token
            elif token:
                raise EvidenceError(f'{path}: unsupported pagination; evidence incomplete')
            else:
                return rows
        raise EvidenceError('Pagination limit exceeded; evidence incomplete')


def canonical(client):
    target = client.target
    pr = client.get(target.path)
    repo = pr['repository']
    project = repo['project']
    if pr['pullRequestId'] != target.pr or target.repository.casefold() not in (repo['id'].casefold(), repo['name'].casefold()) or target.project.casefold() not in (project['id'].casefold(), project['name'].casefold()):
        raise EvidenceError('Returned PR identity does not match the requested project/repository/PR')
    client.target = Identity(target.org, project['id'], repo['id'], target.pr)
    return pr


STATUSES = {0: 'unknown', 1: 'active', 2: 'fixed', 3: 'wontFix', 4: 'closed', 5: 'byDesign', 6: 'pending'}


def feedback(thread):
    """Keep all non-deleted human/bot text, including replies after a deleted root."""
    if thread.get('isDeleted') is True:
        return None
    comments = thread.get('comments')
    if not isinstance(comments, list):
        raise EvidenceError('Thread comments unreadable')
    visible = []
    for c in comments:
        if c.get('isDeleted') is True or c.get('commentType') in ('system', 3, 'codeChange', 2):
            continue
        if c.get('commentType') not in ('text', 1):
            raise EvidenceError('Unknown comment type; feedback cannot be classified')
        if not isinstance(c.get('content'), str):
            raise EvidenceError('Comment content unreadable')
        if c['content'].strip():
            visible.append(c)
    if not visible:
        return None
    status = STATUSES.get(thread.get('status'), thread.get('status'))
    if status not in STATUSES.values():
        status = 'unknown'
    return {**thread, 'status': status, 'comments': visible}
