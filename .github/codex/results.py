import json
import pathlib
import sys


p = pathlib.Path(sys.argv[1])
summary = {}
ordinary_skips = {
    'TestCommand_BeforeAfterFuncShellCompletion',
    'TestIntFlagExt/valid_hex',
    'TestIntFlagExt/valid_hex_default',
    'TestFlagValue',
    "TestHelpCommand_FullName/cmd_help's_FullName",
    "TestHelpCommand_FullName/cmd_help's_FullName_via_flag",
}
template_skips = {
    'TestShowCommandHelp_HelpPrinterCustom/custom_template_command',
    'TestShowCommandHelp_Customtemplate',
    'TestShowRootCommandHelp_HelpPrinter/custom-template-command',
    'TestShowRootCommandHelp_HelpPrinterCustom/custom-template-command',
    'TestShowRootCommandHelp_CustomAppTemplate',
    'TestPrintHelpCustomTemplateError',
}
for label in ['original-default', 'original-no-template', 'fixed-default', 'fixed-no-template', 'full-default', 'full-no-template']:
    events = [json.loads(s) for s in (p / (label + '.log')).read_text().splitlines() if s.startswith('{')]
    tests = {e['Test']: e['Action'] for e in events if e.get('Test') and e.get('Action') in ('pass', 'fail', 'skip')}
    packages = {e['Package']: e['Action'] for e in events if not e.get('Test') and e.get('Action') in ('pass', 'fail', 'skip')}
    raw = int((p / (label + '-exit.txt')).read_text())
    summary[label] = {'rawExit': raw, 'namedPassEvents': sum(v == 'pass' for v in tests.values()), 'namedFailures': [n for n, v in tests.items() if v == 'fail'], 'namedSkips': [n for n, v in tests.items() if v == 'skip'], 'packages': packages}
    if label.startswith('original'):
        scenarios = [n for n in tests if n.endswith('/root') or n.endswith('/subcommand') or n == 'TestCommand_StopOnNthArg_PersistentFlagsBeforeBoundary' or n.startswith('TestCommand_StopOnNthArg_Process/')]
        assert raw == 1 and len(scenarios) == 21, summary[label]
        assert sum(tests[n] == 'fail' for n in scenarios) == 17, summary[label]
        assert sum(tests[n] == 'pass' for n in scenarios) == 4, summary[label]
    else:
        expected_skips = set()
        if label.startswith('full'):
            expected_skips = ordinary_skips | (template_skips if label.endswith('no-template') else set())
        assert raw == 0 and tests and not any(v == 'fail' for v in tests.values()), summary[label]
        assert {n for n, v in tests.items() if v == 'skip'} == expected_skips, summary[label]
        assert packages and all(v == 'pass' for v in packages.values()), summary[label]
for label in ['vet', 'binary-size', 'diffcheck']:
    raw = int((p / (label + '-exit.txt')).read_text())
    summary[label] = {'rawExit': raw}
    assert raw == 0, summary[label]
(p / 'native-summary.json').write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
