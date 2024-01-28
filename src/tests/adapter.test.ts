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


	let dc: DebugClient;

	setup( () => {
		dc = new DebugClient(BIN_DEBUG_ADAPTER, "", 'ahkdbg');
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
					program: PROGRAM , 
					AhkExecutable: RUNTIME
				}),
				dc.waitForEvent('terminated')
			]);
		});

		test('should stop on debugger statement', () => {

			const PROGRAM = Path.join(DATA_ROOT, 'simple/simple_break.ahk');
			const DEBUGGER_LINE = 3;

			return Promise.all([
				dc.configurationSequence(),
				dc.launch({ program: PROGRAM, stopOnEntry: true, AhkExecutable: RUNTIME}),
				dc.assertStoppedLocation('entry', { line: DEBUGGER_LINE })
			]);
		});
	});

	suite('setBreakpoints', () => {

		const PROGRAM = Path.join(DATA_ROOT, 'simple/simple_break.ahk');
		const BREAKPOINT_LINE = 13;

		test('should stop on a breakpoint', () => {
			return dc.hitBreakpoint({ program: PROGRAM, AhkExecutable: RUNTIME }, { path: PROGRAM, line: BREAKPOINT_LINE } );
		});
	});

	suite('output events', () => {

		const PROGRAM = Path.join(DATA_ROOT, 'simple/simple_out.ahk');

		test('stdout and stderr events should be complete and in correct order', () => {
			return Promise.all([
				dc.configurationSequence(),
				dc.launch({ program: PROGRAM, AhkExecutable: RUNTIME, captureStreams: true }),
                dc.continueRequest({threadId: 1}),
				dc.assertOutput('stdout', "Hello stdout 0\nHello stdout 1\nHello stdout 2\n"),
				dc.assertOutput('stderr', "Hello stderr 0\nHello stderr 1\nHello stderr 2\n")
			]);
		});
	});
});
