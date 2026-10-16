"""Offline regressions for host input, routing and session proposal ownership."""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'synapse-graph-memory' / 'scripts'
sys.path.insert(0, str(SCRIPTS))


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AuditRegressions(unittest.TestCase):
    def test_explicit_target_wins_over_unrelated_feature(self):
        import ingest_memory as ingest
        nodes = [{'path': 'meta/mod_billing.md', 'frontmatter': {'id': 'mod_billing', 'type': 'module'}, 'body': ''},
                 {'path': 'meta/feat_checkout.md', 'frontmatter': {'id': 'feat_checkout', 'type': 'feature'}, 'body': ''}]
        action, target = ingest.choose_target(nodes, ingest.extract('[mod_billing] 源码变更: src/services/billing.py'))
        self.assertEqual((action, target), ('update_node', 'meta/mod_billing.md'))

    def test_no_match_does_not_select_arbitrary_feature(self):
        import ingest_memory as ingest
        nodes = [{'path': 'meta/feat_checkout.md', 'frontmatter': {'id': 'feat_checkout', 'type': 'feature'}, 'body': ''}]
        self.assertEqual(ingest.choose_target(nodes, ingest.extract('background job changed'))[0], 'create_node')

    def test_adapter_migrates_old_command_and_sets_budget(self):
        adapter = load(ROOT / 'adapters/hosts/claude_code.py', 'claude_adapter_audit')
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            adapter.install(project, SCRIPTS.parent)
            path = project / '.claude/settings.json'
            settings = json.loads(path.read_text(encoding='utf-8'))
            cmd = settings['hooks']['UserPromptSubmit'][0]['hooks'][0]
            cmd['command'] = cmd['command'].replace('${CLAUDE_PROJECT_DIR}', '$CLAUDE_PROJECT_ROOT')
            settings['hooks']['UserPromptSubmit'][0]['hooks'].append({'type': 'command', 'command': 'echo custom'})
            path.write_text(json.dumps(settings), encoding='utf-8')
            adapter.install(project, SCRIPTS.parent)
            settings = json.loads(path.read_text(encoding='utf-8'))
            hooks = [h for e in settings['hooks']['UserPromptSubmit'] for h in e['hooks']]
            self.assertEqual(sum('prefetch_context.py' in h['command'] for h in hooks), 1)
            self.assertTrue(any('${CLAUDE_PROJECT_DIR}' in h['command'] for h in hooks))
            self.assertTrue(any(h['command'] == 'echo custom' for h in hooks))
            self.assertEqual(settings['hooks']['SessionEnd'][0]['hooks'][0]['timeout'], 60)

    def test_prefetch_from_subdirectory_uses_host_root(self):
        adapter = load(ROOT / 'adapters/hosts/claude_code.py', 'claude_adapter_prefetch')
        with tempfile.TemporaryDirectory(prefix='synapse space ') as tmp:
            project = Path(tmp)
            (project / 'src').mkdir()
            (project / 'MEMORY_MAP.json').write_text(json.dumps({'nodes': [{'id': 'mod_payment', 'tags': ['payment'], 'aliases': [], 'summary': 'payment'}]}), encoding='utf-8')
            adapter.install(project, SCRIPTS.parent)
            settings = json.loads((project / '.claude/settings.json').read_text(encoding='utf-8'))
            command = settings['hooks']['UserPromptSubmit'][0]['hooks'][0]['command']
            # Expand the host placeholder exactly as a shell would, then execute argv.
            self.assertIn('${CLAUDE_PROJECT_DIR}', command)
            result = subprocess.run([sys.executable, str(SCRIPTS / 'prefetch_context.py'), '--project', str(project), '--prompt', 'payment'], cwd=project / 'src', capture_output=True, text=True, encoding='utf-8', check=True)
            self.assertIn('mod_payment', result.stdout)

    def test_transcript_only_reads_user_text_and_needs_review(self):
        import auto_observe
        import session_memory
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            transcript = project / 'session.jsonl'
            entries = [{'type': 'assistant', 'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': "we'll use redis for billing"}]}},
                       {'type': 'user', 'message': {'role': 'user', 'content': [{'type': 'tool_result', 'content': "we'll use mysql"}, {'type': 'text', 'text': "we'll use postgres for billing"}]}}]
            transcript.write_text('\n'.join(json.dumps(x) for x in entries), encoding='utf-8')
            text = auto_observe.read_transcript(transcript, user_only=True)
            self.assertIn('postgres', text)
            self.assertNotIn('redis', text)
            self.assertNotIn('mysql', text)
            proposals = auto_observe.extract_conversation_signals(text)
            high, low = session_memory.partition(proposals, project)
            self.assertFalse(high)
            self.assertTrue(low)

    def test_empty_partitions_replace_prior_session_files(self):
        import session_memory
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / 'meta').mkdir()
            (project / 'meta/mod_billing.md').write_text('# Billing', encoding='utf-8')
            proposal = {'target_node': 'mod_billing', 'content': 'source changed', 'source': 'git_diff', 'confidence': 90}
            out = project / 'proposals'
            session_memory.write_partitions(out, [proposal], project, 'first')
            session_memory.write_partitions(out, [], project, 'second')
            for name in ['auto_apply.json', 'needs_review.json']:
                payload = json.loads((out / name).read_text(encoding='utf-8'))
                self.assertEqual(payload['proposals'], [])
                self.assertEqual(payload['session_id'], 'second')

    def test_session_cli_consumes_host_transcript_and_queues_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            transcript = project / 'session.jsonl'
            transcript.write_text(json.dumps({'type': 'user', 'message': {'role': 'user', 'content': "we'll use postgres for billing"}}), encoding='utf-8')
            payload = {'session_id': 'audit-session', 'cwd': str(project), 'transcript_path': str(transcript)}
            proc = subprocess.run([sys.executable, '-X', 'utf8', str(SCRIPTS / 'session_memory.py'), '--project', str(project)], input=json.dumps(payload), capture_output=True, text=True, encoding='utf-8', check=True)
            self.assertIn('1 queued', proc.stdout)
            inbox = json.loads((project / '.synapse/inbox.json').read_text(encoding='utf-8'))
            self.assertIn('postgres', inbox['items'][0]['content'])
            self.assertFalse((project / 'meta').exists())

    def test_structured_target_is_written_without_rerouting(self):
        import session_memory
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / 'meta').mkdir()
            for node in ['mod_billing', 'feat_checkout']:
                (project / f'meta/{node}.md').write_text(f'# {node}\n\n## Change Log\nNone.\n', encoding='utf-8')
            proposal = {'target_node': 'mod_billing', 'content': 'source changed', 'source': 'git_diff', 'confidence': 90}
            result = session_memory.apply_proposals(project, [proposal])
            self.assertEqual(result, (1, 0))
            self.assertIn('source changed', (project / 'meta/mod_billing.md').read_text(encoding='utf-8'))
            self.assertNotIn('source changed', (project / 'meta/feat_checkout.md').read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()
