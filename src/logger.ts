import * as vscode from 'vscode';

export class Logger {
    private _logger: vscode.OutputChannel;
    constructor() {
        this._logger = vscode.window.createOutputChannel('AutoHotkey Debug');
    }

    public info(message: string) {
        this._logger.appendLine(`[Info] ${message}`);
    } 

    public warn(message: string) {
        this._logger.appendLine(`[Warn] ${message}`);
    }
}