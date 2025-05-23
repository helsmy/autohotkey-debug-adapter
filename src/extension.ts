'use strict';

import * as vscode from 'vscode';
import { WorkspaceFolder, DebugConfiguration, ProviderResult, CancellationToken } from 'vscode';
import { Logger } from './logger'
import { join } from 'path';
import { existsSync } from 'fs'

interface AutoHotkeyDebugConfiguration extends DebugConfiguration{
	stopOnEntry: boolean
	captureStreams: boolean
	/** @deprecated */
	AhkExecutable: string
	runtime: string
	args: []
	port: number|string
}
const logger = new Logger();


export function activate(context: vscode.ExtensionContext) {
	logger.info('Activating.');

	// register a configuration provider for 'mock' debug type
	const provider = new DebugConfigurationProvider();
	context.subscriptions.push(vscode.debug.registerDebugConfigurationProvider('ahkdbg', provider));

	// build debug adapters:
	let factory = new DebugAdapterExecutableFactory(context.extensionMode, context.extensionUri);

	context.subscriptions.push(vscode.debug.registerDebugAdapterDescriptorFactory('ahkdbg', factory));
	if ('dispose' in factory) {
		context.subscriptions.push(factory);
	}

	logger.info('Activated.');
}

export function deactivate() {
	// nothing to do
}

class DebugConfigurationProvider implements vscode.DebugConfigurationProvider {

	/**
	 * Massage a debug configuration just before a debug session is being launched,
	 * e.g. add all missing attributes to the debug configuration.
	 */
	resolveDebugConfiguration(folder: WorkspaceFolder | undefined, config: AutoHotkeyDebugConfiguration, token?: CancellationToken): ProviderResult<DebugConfiguration> {

		// if launch.json is missing or empty
		if (!config.type && !config.request && !config.name) {
			const editor = vscode.window.activeTextEditor;
			if (editor && editor.document.languageId === 'ahk') {
				logger.info('Can not find launch.json. Use default settings.');
				config.type = 'ahkdbg';
				config.name = 'Launch';
				config.request = 'launch';
				config.program = '${file}';
				config.stopOnEntry = false;
				config.captureStreams = true;
				config.AhkExecutable = ''; // Empty value to make da acquire executable path
				config.runtime = '';       // Empty value to make da acquire executable path
				config.args = []
				config.port = 9005;
				// config.log = false;
			}
		}

		if (!config.program) {
			return vscode.window.showInformationMessage("Cannot find a program to debug").then(_ => {
				return undefined;	// abort launch
			});
		}
		logger.info(`Settings: ${JSON.stringify(config)}`);
		return config;
	}
}

class DebugAdapterExecutableFactory implements vscode.DebugAdapterDescriptorFactory {
	constructor(
		private readonly mode: vscode.ExtensionMode,
		private readonly extensionUri: vscode.Uri
	) {
		
	} 
	createDebugAdapterDescriptor(_session: vscode.DebugSession, executable: vscode.DebugAdapterExecutable | undefined): ProviderResult<vscode.DebugAdapterDescriptor> {
		// param "executable" contains the executable optionally specified in the package.json (if any)

		// use the executable specified in the package.json if it exists or determine it based on some other information (e.g. the session)
		if (!executable) {
			logger.warn('No executable debugadapter set. Use default executable path');
			const command = vscode.Uri.joinPath(this.extensionUri, "./bin/debugadapter.exe").fsPath;
			// no option needed
			// const options = {};
			executable = new vscode.DebugAdapterExecutable(command);
		}
		// if under dev
		if (this.mode !== vscode.ExtensionMode.Production) {
			const runtime = vscode.Uri.joinPath(this.extensionUri, ".\\bin\\AutoHotKey.exe").fsPath;
			if (!existsSync(runtime))
				// vscode.window.showErrorMessage(`Autohotkey runtime is not exist in '${runtime}'`);
				throw Error(`Autohotkey runtime is not exist. Uncompiled debug adapter needs runtime in '${runtime}'.`);
			
			executable = new vscode.DebugAdapterExecutable(
				runtime,
				[vscode.Uri.joinPath(this.extensionUri, ".\\ahkdbg\\debugadapter.ahk").fsPath]
			);
			logger.info(`factory ${JSON.stringify(executable)}`);
		}
		// make VS Code launch the DA executable
		return executable;
	}

	public dispose() {
		return
	}

}
