'use strict';

import * as vscode from 'vscode';
import { WorkspaceFolder, DebugConfiguration, ProviderResult, CancellationToken } from 'vscode';
import { Logger } from './logger'
import { join } from 'path';
import { existsSync, readFileSync } from 'fs'

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

/**
 * Split an argument string like a shell would: on whitespace, keeping
 * double-quoted sections together (quotes removed).
 */
function parseArgs(input: string): string[] {
	const args: string[] = [];
	let current = '';
	let inQuotes = false;
	for (const ch of input.trim()) {
		if (ch === '"') {
			inQuotes = !inQuotes;
		} else if (/\s/.test(ch) && !inQuotes) {
			if (current) {
				args.push(current);
				current = '';
			}
		} else {
			current += ch;
		}
	}
	if (current) {
		args.push(current);
	}
	return args;
}

let fallbackMessages: { [key: string]: string } | undefined;

/**
 * Wrapper around vscode.l10n.t with a manual fallback: if VS Code did not
 * load the l10n bundle (observed in development hosts), read
 * l10n/bundle.l10n.<language>.json from the extension directory ourselves.
 */
function t(message: string): string {
	if (vscode.l10n.bundle) {
		return vscode.l10n.t(message);
	}
	return fallbackMessages && fallbackMessages[message] || message;
}

function loadFallbackBundle(extensionUri: vscode.Uri) {
	if (vscode.l10n.bundle) {
		return;
	}
	const lang = vscode.env.language;
	if (lang === 'en' || lang.startsWith('en-')) {
		return;
	}
	const candidates = [lang, lang.split('-')[0]];
	for (const candidate of candidates) {
		const file = vscode.Uri.joinPath(extensionUri, 'l10n', `bundle.l10n.${candidate}.json`);
		try {
			const content = readFileSync(file.fsPath, 'utf8');
			fallbackMessages = JSON.parse(content);
			logger.info(`Loaded fallback l10n bundle: ${file.fsPath}`);
			return;
		} catch (e) {
			// try next candidate
		}
	}
}


export function activate(context: vscode.ExtensionContext) {
	logger.info('Activating.');
	logger.info(`l10n bundle: ${JSON.stringify(vscode.l10n.bundle)}`);
	logger.info(`env.language: ${vscode.env.language}`);
	loadFallbackBundle(context.extensionUri);

	// ${command:...} substitution in launch.json requires a string result,
	// so the raw input is returned and parsed in resolveDebugConfiguration
	context.subscriptions.push(vscode.commands.registerCommand('autohotkey-debug.pickArgs', async (): Promise<string> => {
		const input = await vscode.window.showInputBox({
			placeHolder: '',
			prompt: t('Enter program arguments (space separated, quote args containing spaces)'),
			ignoreFocusOut: true
		});
		// cancelled by user: fall back to no arguments instead of aborting the launch
		return input ?? '';
	}));

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
			return vscode.window.showInformationMessage(t("Cannot find a program to debug")).then(_ => {
				return undefined;	// abort launch
			});
		}
		if (typeof config.args === 'string') {
			config.args = parseArgs(config.args) as [];
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
				[
					vscode.Uri.joinPath(this.extensionUri, ".\\ahkdbg\\debugadapter.ahk").fsPath,
					'--loglevelinfo'
				]
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
