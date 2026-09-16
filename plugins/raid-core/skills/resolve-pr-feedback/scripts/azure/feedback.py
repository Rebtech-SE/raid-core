#!/usr/bin/env python3
"""List Azure feedback or apply one explicitly selected reply/status; never fixes code or merges."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from urllib.parse import parse_qs, quote, urlsplit
from client import Client, EvidenceError, canonical, feedback, identity, positive


def digest(thread):
    return hashlib.sha256(json.dumps(thread, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def target_thread(url, explicit=None):
    query = parse_qs(urlsplit(url).query)
    values = query.get('discussionId', [])
    if len(values) > 1:
        raise EvidenceError('Ambiguous discussionId')
    embedded = positive(values[0]) if values else None
    if embedded and explicit and embedded != positive(explicit):
        raise EvidenceError('Conflicting targeted thread IDs')
    return embedded or (positive(explicit) if explicit else None)


def thread_record(client, raw):
    value = feedback(raw)
    if value is None:
        return None
    tid = positive(raw['id'])
    api_url = client.target.base + '/_apis/' + client.target.path + f'/threads/{tid}?api-version=7.1'
    return {'source_id': api_url, 'kind': 'thread', 'thread_url': api_url,
        'thread_id': tid, 'expected_thread': digest(raw), 'feedback': value}


def fetch(client, thread_id=None):
    pr = canonical(client)
    rows = [client.get(client.target.path + f'/threads/{thread_id}')] if thread_id else client.collection(client.target.path + '/threads')
    items = []
    for raw in rows:
        if thread_id and raw.get('id') != thread_id:
            raise EvidenceError('Targeted response contains a different thread')
        record = thread_record(client, raw)
        if record and (thread_id or record['feedback']['status'] in ('active', 'pending', 'unknown')):
            items.append(record)
    return {'provider': 'azure-devops-services', 'identity': vars(client.target), 'url': client.target.url,
        'head': pr['lastMergeSourceCommit']['commitId'], 'pr': pr, 'threads': items}


def mutate(client, action, tid, expected_head, expected_thread, content=None, status=None):
    pr = canonical(client)
    if pr.get('status') != 'active' or pr.get('forkSource'):
        raise EvidenceError('Only active, same-repository Azure PR heads are supported for feedback mutation')
    if pr['lastMergeSourceCommit']['commitId'] != expected_head:
        raise EvidenceError('PR head changed; reassess before mutation')
    branch = pr['sourceRefName']
    values = client.collection('git/repositories/' + quote(client.target.repository, safe='') + '/refs',
        {'filter': branch.removeprefix('refs/')}, paging='token')
    if [x.get('objectId') for x in values if x.get('name') == branch] != [expected_head]:
        raise EvidenceError('Source branch moved beyond the assessed PR head')
    path = client.target.path + f'/threads/{positive(tid)}'
    raw = client.get(path)
    if raw.get('id') != tid or digest(raw) != expected_thread:
        raise EvidenceError('Thread changed; fetch and reassess before mutation')
    item = feedback(raw)
    if not item or item['status'] not in ('active', 'pending'):
        raise EvidenceError('Only live unresolved text discussions may be changed')
    if action == 'reply':
        if not isinstance(content, str) or not content.strip():
            raise EvidenceError('Reply body must not be empty')
        created, _ = client.request(path + '/comments', method='POST', body={'content': content,
            'parentCommentId': positive(item['comments'][0]['id']), 'commentType': 1})
        created_id = positive(created['id'])
        if any(c.get('id') == created_id for c in raw['comments']):
            raise EvidenceError('Reply response reused an existing comment ID; inspect before retrying')
    elif action == 'resolve':
        if status not in ('fixed', 'wontFix', 'byDesign', 'closed'):
            raise EvidenceError('A documented resolution status is required')
        client.request(path, method='PATCH', body={'status': status})
    else:
        raise EvidenceError('Unsupported mutation')
    updated = client.get(path)
    if action == 'resolve' and (feedback(updated) or {}).get('status') != status:
        raise EvidenceError('Resolution readback did not match; inspect before retrying')
    if action == 'reply' and not any(c.get('id') == created_id and c.get('content') == content and not c.get('isDeleted') for c in updated.get('comments', [])):
        raise EvidenceError('Reply readback did not match; inspect before retrying')
    return thread_record(client, updated)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['list', 'reply', 'resolve'])
    parser.add_argument('--url', required=True)
    parser.add_argument('--pr', type=int)
    parser.add_argument('--thread-id', type=positive)
    parser.add_argument('--expected-head')
    parser.add_argument('--expected-thread')
    parser.add_argument('--body-file', type=Path)
    parser.add_argument('--status', choices=['fixed', 'wontFix', 'byDesign', 'closed'])
    args = parser.parse_args()
    try:
        tid = target_thread(args.url, args.thread_id)
        client = Client(identity(args.url, args.pr))
        if args.action == 'list':
            result = fetch(client, tid)
        else:
            if not tid or not args.expected_head or not args.expected_thread:
                raise EvidenceError('Mutation requires exact thread ID and assessed head/thread digests')
            result = mutate(client, args.action, tid, args.expected_head, args.expected_thread,
                args.body_file.read_text() if args.body_file else None, args.status)
        print(json.dumps(result))
        return 0
    except (EvidenceError, KeyError, TypeError, ValueError, AttributeError, OSError, subprocess.TimeoutExpired) as error:
        print(json.dumps({'kind': 'error', 'detail': str(error)}))
        return 2


if __name__ == '__main__':
    sys.exit(main())
