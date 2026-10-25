/*---------------------------------------------------------------------------------------------
 * Modified for this project from Microsoft Example under MIT
 * E2E Test for debug adapter 
 *--------------------------------------------------------------------------------------------*/

"use strict";

import assert = require('assert');
import * as Path from 'path';
import {DebugClient} from 'vscode-debugadapter-testsupport';
import {DebugProtocol} from 'vscode-debugprotocol';

suite('Node Debug Adapter', () => {

	const PROJECT_ROOT = Path.join(__dirname, '../../');
	const DATA_ROOT = Path.join(PROJECT_ROOT, 'testdata/');

	const DEBUG_ADAPTER = Path.join(PROJECT_ROOT, 'ahkdbg', 'debugAdapter.ahk');
    const RUNTIME = Path.join(PROJECT_ROOT, '/bin/AutoHotkey.exe')
	const BIN_DEBUG_ADAPTER = Path.join(PROJECT_ROOT, 'bin', 'debugAdapter.exe');

	const LAUNCH_OPTION: any = {AhkExecutable: RUNTIME , port: 9005}

	let dc: DebugClient;

	setup( () => {
		const isDevMode = process.argv[process.argv.length - 1];
		dc = isDevMode == '--dev'? new DebugClient(RUNTIME, DEBUG_ADAPTER, 'ahkdbg') : 
							new DebugClient(BIN_DEBUG_ADAPTER, '', 'ahkdbg');
		return dc.start();
	});

	teardown( () => dc.stop() );


	suite('basic', () => {

		test('unknown request should produce error', done => {
			dc.send('illegal_request').then(() => {
				done(new Error("does not report error on unknown request"));
			}).catch(() => {
				done();
			});
		});
	});

	suite('initialize', () => {

		test('should produce error for invalid \'pathFormat\'', done => {
			dc.initializeRequest({
				adapterID: 'ahk',
				linesStartAt1: true,
				columnsStartAt1: true,
				pathFormat: 'url'
			}).then(response => {
				done(new Error("does not report error on invalid 'pathFormat' attribute"));
			}).catch(err => {
				// error expected
				done();
			});
		});
	});

	suite('launch', () => {
		test('should run program to the end', async () => {

			const PROGRAM = Path.join(DATA_ROOT, 'simple/simple.ahk');

			return Promise.all([
				dc.configurationSequence(),
				dc.launch({
					...LAUNCH_OPTION,
					program: PROGRAM 
				}),
				dc.waitForEvent('terminated')
			]).catch(err => err);
		});

		test('should stop on debugger statement', async () => {

			const PROGRAM = Path.join(DATA_ROOT, 'simple/simple_break.ahk');
			const DEBUGGER_LINE = 3;

			try {
				return await Promise.all([
					dc.configurationSequence(),
					dc.launch({ ...LAUNCH_OPTION, program: PROGRAM, stopOnEntry: true}),
					dc.assertStoppedLocation('entry', { line: DEBUGGER_LINE })
				]);
			} catch (err) {
				return err;
			}
		});
	});

	suite('setBreakpoints', async () => {

		const PROGRAM = Path.join(DATA_ROOT, 'simple/simple_break.ahk');
		const BREAKPOINT_LINE = 13;

		test('should stop on a breakpoint', async () => {
			try {
				const res = await dc.hitBreakpoint(
					{ ...LAUNCH_OPTION, program: PROGRAM},
					{ path: PROGRAM, line: BREAKPOINT_LINE },
					{line: BREAKPOINT_LINE}
				);
			} catch (err) {
				return err;
			}
		});

		test('breakpoint response should have valid source structure', async () => {
			// Arrange
			// 'initialized' is only emitted after launch sends 'initialize',
			// and the launch response is deferred until 'configurationDone',
			// so launch must run concurrently with the configuration sequence.
			// Breakpoints must be set BEFORE configurationDone: once the debuggee
			// is resumed it may exit and breakpoint_set then fails (verified:false).
			const initializedPromise = dc.waitForEvent('initialized');
			const launchPromise = dc.launch({ ...LAUNCH_OPTION, program: PROGRAM });
			await initializedPromise;

			// Act
			const response = await dc.setBreakpointsRequest({
				source: { path: PROGRAM },
				breakpoints: [{ line: BREAKPOINT_LINE }]
			});
			await dc.configurationDoneRequest();
			await launchPromise;

			// Assert
			const breakpoint = response.body.breakpoints[0];
			assert.ok(breakpoint.source, 'breakpoint should have source');
			assert.strictEqual(typeof breakpoint.source.path, 'string', 'source.path should be a string, not an object');
			assert.strictEqual(breakpoint.source.path, PROGRAM, 'source.path should match program path');
			assert.ok(breakpoint.source.name, 'source should have name');
			assert.strictEqual(typeof breakpoint.source.sourceReference, 'number', 'sourceReference should be a number');
		});
	});

	suite('output events', () => {

		const PROGRAM = Path.join(DATA_ROOT, 'simple/simple_out.ahk');

		test('stdout and stderr events should be complete and in correct order', () => {
			return Promise.all([
				dc.configurationSequence(),
				dc.launch({ ...LAUNCH_OPTION, program: PROGRAM, captureStreams: true }),
                dc.continueRequest({threadId: 1}),
				dc.assertOutput('stdout', "Hello stdout 0\nHello stdout 1\nHello stdout 2\n"),
				dc.assertOutput('stderr', "Hello stderr 0\nHello stderr 1\nHello stderr 2\n")
			]);
		});
	});

	suite('array folding', () => {

		const V2_AHK = 'C:/Program Files/AutoHotkey/v2/AutoHotkey64.exe';

		async function variablesOf(dc: DebugClient, ref: number): Promise<DebugProtocol.Variable[]> {
			const res = await dc.variablesRequest({ variablesReference: ref });
			return res.body.variables;
		}

		async function stopAt(dc: DebugClient, program: string, line: number): Promise<DebugProtocol.StackFrame[]> {
			return await dc.hitBreakpoint({ ...LAUNCH_OPTION, AhkExecutable: V2_AHK, program }, { path: program, line });
		}

		function findVar(vars: DebugProtocol.Variable[], name: string): DebugProtocol.Variable {
			const v = vars.find(v => v.name === name);
			assert.ok(v, `variable '${name}' not found`);
			return v;
		}

		test('short array should not be folded', async () => {
			const PROGRAM = Path.join(DATA_ROOT, 'arrays/large_array_v2.ahk');
			await stopAt(dc, PROGRAM, 4);
			const stack = await dc.stackTraceRequest({ threadId: 1 });
			const scopes = await dc.scopesRequest({ frameId: stack.body.stackFrames[0].id });
			const localRef = scopes.body.scopes.find(s => s.name === 'Global')!.variablesReference;
			const locals = await variablesOf(dc, localRef);
			const arr = findVar(locals, 'arr');
			assert.strictEqual(arr.variablesReference > 0, true, 'array should be expandable');
			const items = await variablesOf(dc, arr.variablesReference);
			assert.ok(items.some(v => v.name === '[1]'), 'item 1 should be listed directly');
		});

		test('long array should be folded into page metas', async () => {
			const PROGRAM = Path.join(DATA_ROOT, 'arrays/huge_array_v2.ahk');
			await stopAt(dc, PROGRAM, 4);
			const stack = await dc.stackTraceRequest({ threadId: 1 });
			const scopes = await dc.scopesRequest({ frameId: stack.body.stackFrames[0].id });
			const localRef = scopes.body.scopes.find(s => s.name === 'Global')!.variablesReference;
			const locals = await variablesOf(dc, localRef);
			const arr = findVar(locals, 'bigArr');
			assert.strictEqual(arr.variablesReference > 0, true, 'array should be expandable');

			// v2 debugee with max_children=100: page 0 holds n0=99 items (+<base>), later pages 100 -> 16 pages
			// <base> is an attribute of the array itself: shown first, outside the folding
			const level1 = await variablesOf(dc, arr.variablesReference);
			assert.deepStrictEqual(level1.map(v => v.name), ['<base>', '[1-999]', '[1000-1500]'], 'root folding groups');

			// expand a 10-page group: first page 99 items, later pages 100
			const group1 = findVar(level1, '[1-999]');
			const level2 = await variablesOf(dc, group1.variablesReference);
			assert.strictEqual(level2.length, 10, 'group should contain 10 pages');
			assert.strictEqual(level2[0].name, '[1-99]');
			assert.strictEqual(level2[9].name, '[900-999]');

			// last group holds the remaining 6 pages (16 total)
			const group2 = findVar(level1, '[1000-1500]');
			const level2b = await variablesOf(dc, group2.variablesReference);
			assert.strictEqual(level2b.length, 6);
			assert.strictEqual(level2b[5].name, '[1500-1500]');

			// expand page leaves: values must align with indices, across a page boundary
			// <base> is only shown at the outer level, never inside a folded page
			const page1 = findVar(level2, '[1-99]');
			const page1Items = await variablesOf(dc, page1.variablesReference);
			assert.strictEqual(page1Items.length, 99);
			assert.strictEqual(page1Items[0].name, '[1]');
			assert.strictEqual(page1Items[0].value, '"item1"');
			const page2 = findVar(level2, '[100-199]');
			const page2Items = await variablesOf(dc, page2.variablesReference);
			assert.strictEqual(page2Items.length, 100);
			assert.strictEqual(page2Items[0].name, '[100]');
			assert.strictEqual(page2Items[0].value, '"item100"');
		});
	});
});
