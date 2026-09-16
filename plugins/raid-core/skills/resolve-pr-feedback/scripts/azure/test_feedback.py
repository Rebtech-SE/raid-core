import copy
import unittest
from client import EvidenceError, Identity
from feedback import digest, fetch, mutate, target_thread

HEAD = 'a' * 40


class Fake:
    def __init__(self):
        self.target = Identity('org', 'project', 'repo', 12)
        self.pr = {'pullRequestId': 12, 'status': 'active', 'sourceRefName': 'refs/heads/work',
            'repository': {'id': 'repo', 'name': 'repo', 'project': {'id': 'project', 'name': 'project'}},
            'lastMergeSourceCommit': {'commitId': HEAD}}
        self.thread = {'id': 9, 'status': 'active', 'comments': [
            {'id': 1, 'commentType': 'text', 'content': 'Fix this', 'author': {'id': 'human'}}]}
        self.writes, self.reads = [], []
        self.branch_head = HEAD

    def get(self, path):
        self.reads.append(path)
        return copy.deepcopy(self.thread if '/threads/' in path else self.pr)

    def collection(self, path, query=None, paging=None):
        self.reads.append(path)
        if path.endswith('/refs'):
            return [{'name': 'refs/heads/work', 'objectId': self.branch_head}]
        return [copy.deepcopy(self.thread)]

    def request(self, path, method, body):
        self.writes.append((path, method, body))
        if method == 'POST':
            self.thread['comments'].append({'id': 2, 'commentType': 'text', 'content': body['content']})
        else:
            self.thread['status'] = body['status']
        return ({'id': 2} if method == 'POST' else {}), None


class FeedbackTests(unittest.TestCase):
    def test_list_is_read_only_and_targeted_fetch_stays_targeted(self):
        c = Fake(); result = fetch(c, 9)
        self.assertEqual(c.writes, [])
        self.assertTrue(c.reads[-1].endswith('/threads/9'))
        self.assertEqual(len(result['threads']), 1)
        self.assertIn('/project/_apis/git/repositories/repo/pullRequests/12/threads/9', result['threads'][0]['source_id'])
        self.assertEqual(result['threads'][0]['expected_thread'], digest(c.thread))

    def test_reply_payload_is_data_then_resolution_verifies_new_digest(self):
        c = Fake(); text = 'Fixed in abc123: literal $(secret) `do not execute`\nSecond line'
        record = mutate(c, 'reply', 9, HEAD, digest(c.thread), text)
        self.assertEqual(c.writes[0], ('git/repositories/repo/pullRequests/12/threads/9/comments',
            'POST', {'content': text, 'parentCommentId': 1, 'commentType': 1}))
        mutate(c, 'resolve', 9, HEAD, record['expected_thread'], status='fixed')
        self.assertEqual(c.writes[1][1:], ('PATCH', {'status': 'fixed'}))

    def test_reply_readback_requires_new_comment_id(self):
        class WrongReadback(Fake):
            def request(self, path, method, body):
                self.writes.append((path, method, body))
                return {'id': 99}, None
        c = WrongReadback()
        with self.assertRaises(EvidenceError):
            mutate(c, 'reply', 9, HEAD, digest(c.thread), 'Fix this')
        self.assertEqual(len(c.writes), 1)

    def test_changed_head_thread_or_source_ref_prevents_write(self):
        for change in ['head', 'thread', 'branch']:
            c = Fake(); assessed = digest(c.thread)
            if change == 'head': c.pr['lastMergeSourceCommit']['commitId'] = 'b' * 40
            if change == 'thread': c.thread['comments'][0]['content'] = 'New decision'
            if change == 'branch': c.branch_head = 'b' * 40
            with self.assertRaises(EvidenceError):
                mutate(c, 'reply', 9, HEAD, assessed, 'reply')
            self.assertEqual(c.writes, [])

    def test_unknown_deleted_system_and_completed_threads_are_not_mutated(self):
        for kind in ['unknown', 'fixed', 'deleted', 'system']:
            c = Fake()
            if kind == 'deleted': c.thread['isDeleted'] = True
            elif kind == 'system': c.thread['comments'][0]['commentType'] = 'system'
            else: c.thread['status'] = kind
            with self.assertRaises(EvidenceError):
                mutate(c, 'resolve', 9, HEAD, digest(c.thread), status='closed')
            self.assertEqual(c.writes, [])

    def test_targeted_identity_and_no_merge_status(self):
        self.assertEqual(target_thread('https://dev.azure.com/o/p/_git/r/pullrequest/12?discussionId=9'), 9)
        with self.assertRaises(EvidenceError):
            target_thread('https://dev.azure.com/o/p/_git/r/pullrequest/12?discussionId=9', 10)
        c = Fake()
        with self.assertRaises(EvidenceError):
            mutate(c, 'resolve', 9, HEAD, digest(c.thread), status='completed')
        self.assertEqual(c.writes, [])


if __name__ == '__main__':
    unittest.main()
