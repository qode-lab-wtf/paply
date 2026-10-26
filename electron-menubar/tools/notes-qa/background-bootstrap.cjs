// QA only: undo Playwright's background scheduling shortcuts before app ready.
const { app } = require('electron');
for (const key of ['disable-background-timer-throttling','disable-renderer-backgrounding','disable-backgrounding-occluded-windows']) app.commandLine.removeSwitch(key);
require('../../electron-main.js');
