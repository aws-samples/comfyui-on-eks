import { app } from "../../scripts/app.js";
import { api } from "../../scripts/api.js";

const POLL_INTERVAL = 5000;
const MODEL_EXTENSIONS = [".safetensors", ".ckpt", ".pt", ".pth", ".bin"];
const MODEL_WIDGET_TYPES = [
    "ckpt_name", "unet_name", "clip_name", "clip_name1", "clip_name2", "clip_name3",
    "vae_name", "lora_name", "control_net_name", "model_name", "style_model_name",
    "gligen_name", "clip_vision"
];

function isModelWidget(widget) {
    if (MODEL_WIDGET_TYPES.includes(widget.name)) return true;
    if (widget.value && typeof widget.value === "string") {
        return MODEL_EXTENSIONS.some(ext => widget.value.endsWith(ext));
    }
    return false;
}

function injectMissingModelValues() {
    const injected = [];
    const nodes = app.graph._nodes || [];

    for (const node of nodes) {
        if (!node.widgets) continue;
        for (const widget of node.widgets) {
            if (!isModelWidget(widget)) continue;
            if (!widget.value || typeof widget.value !== "string") continue;

            const options = widget.options?.values || [];
            if (options.length === 0 || !options.includes(widget.value)) {
                if (!options.includes(widget.value)) {
                    if (!widget.options) widget.options = {};
                    if (!widget.options.values) widget.options.values = [];
                    widget.options.values.push(widget.value);
                    injected.push({ node: node.id, widget: widget.name, value: widget.value });
                }
            }
        }
    }
    return injected;
}

app.registerExtension({
    name: "comfyui-auto-model-downloader",

    async setup() {
        const originalQueuePrompt = api.queuePrompt.bind(api);

        const originalGraphToPrompt = app.graphToPrompt.bind(app);
        app.graphToPrompt = async function() {
            injectMissingModelValues();
            return originalGraphToPrompt();
        };

        api.queuePrompt = async function(number, { output, workflow }) {
            const result = await checkMissingModels(output);

            if (result.status === "ready") {
                return originalQueuePrompt(number, { output, workflow });
            }

            if (result.status === "bedrock_available") {
                const choice = await showBedrockChoiceDialog(result);
                if (choice === "bedrock") {
                    await checkMissingModels(output, true);
                    return originalQueuePrompt(number, { output, workflow });
                } else if (choice === "download") {
                    await checkMissingModels(output, false, true);
                }
            }

            if (result.missing && result.missing.length > 0) {
                showDownloadNotification(result.missing);
                const ready = await waitForDownloads(result.missing);
                if (ready) {
                    hideDownloadNotification();
                    refreshModelWidgets();
                    return originalQueuePrompt(number, { output, workflow });
                } else {
                    hideDownloadNotification();
                    app.ui.dialog.show("Model download failed or timed out. Please check the server logs.");
                    throw new Error("Model download failed");
                }
            }

            return originalQueuePrompt(number, { output, workflow });
        };
    }
});

function refreshModelWidgets() {
    const nodes = app.graph._nodes || [];
    for (const node of nodes) {
        if (node.widgets) {
            for (const widget of node.widgets) {
                if (isModelWidget(widget) && widget.callback) {
                    try { widget.callback(widget.value); } catch(e) {}
                }
            }
        }
    }
}

async function checkMissingModels(prompt, useBedrock = false, forceDownload = false) {
    try {
        const body = { prompt };
        if (useBedrock) body.use_bedrock = true;
        if (forceDownload) body.force_download = true;

        const resp = await api.fetchApi("/auto-model-downloader/check", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body),
        });
        return await resp.json();
    } catch (e) {
        console.warn("Auto model downloader check failed:", e);
        return { status: "ready", missing: [] };
    }
}

function showBedrockChoiceDialog(result) {
    return new Promise((resolve) => {
        const overlay = document.createElement("div");
        overlay.style.cssText = `
            position: fixed; top: 0; left: 0; width: 100%; height: 100%;
            background: rgba(0,0,0,0.7); z-index: 10001;
            display: flex; align-items: center; justify-content: center;
        `;

        const alternatives = result.bedrock_alternatives || {};
        const altList = Object.entries(alternatives).map(([model, info]) =>
            `<div style="margin: 4px 0; padding: 8px; background: #2a2a4a; border-radius: 4px; font-size: 12px;">
                <span style="color: #4CAF50; font-weight: bold;">${info.node}</span>
                <span style="color: #888; margin-left: 8px;">${info.description}</span>
            </div>`
        ).join("");

        const dialog = document.createElement("div");
        dialog.style.cssText = `
            background: #1a1a2e; color: #e0e0e0; padding: 24px;
            border-radius: 12px; border: 1px solid #4a4a6a;
            box-shadow: 0 8px 24px rgba(0,0,0,0.8);
            max-width: 500px; width: 90%; font-family: sans-serif;
        `;
        dialog.innerHTML = `
            <div style="font-size: 16px; font-weight: bold; margin-bottom: 12px;">
                Bedrock Alternatives Available
            </div>
            <div style="font-size: 13px; color: #aaa; margin-bottom: 16px;">
                ${Object.keys(alternatives).length} missing model(s) can be replaced with Amazon Bedrock — instant access, no download required.
            </div>
            <div style="max-height: 200px; overflow-y: auto; margin-bottom: 16px;">
                ${altList}
            </div>
            <div style="display: flex; gap: 12px; justify-content: flex-end;">
                <button id="amd-btn-download" style="
                    padding: 8px 16px; border-radius: 6px; border: 1px solid #555;
                    background: #333; color: #e0e0e0; cursor: pointer; font-size: 13px;
                ">Download Models Instead</button>
                <button id="amd-btn-bedrock" style="
                    padding: 8px 16px; border-radius: 6px; border: none;
                    background: #4CAF50; color: white; cursor: pointer; font-size: 13px; font-weight: bold;
                ">Use Bedrock (Instant)</button>
            </div>
            <div style="margin-top: 12px; font-size: 11px; color: #666;">
                Tip: Add Bedrock nodes to your workflow for cloud-powered inference without local GPU models.
            </div>
        `;

        overlay.appendChild(dialog);
        document.body.appendChild(overlay);

        dialog.querySelector("#amd-btn-bedrock").onclick = () => {
            overlay.remove();
            resolve("bedrock");
        };
        dialog.querySelector("#amd-btn-download").onclick = () => {
            overlay.remove();
            resolve("download");
        };
    });
}

async function waitForDownloads(models) {
    const timeout = 30 * 60 * 1000;
    const start = Date.now();

    while (Date.now() - start < timeout) {
        await sleep(POLL_INTERVAL);

        try {
            const resp = await api.fetchApi("/auto-model-downloader/status");
            const data = await resp.json();

            const stillDownloading = models.filter(
                m => data.active_downloads[m] && data.active_downloads[m] !== "complete"
            );

            const failed = models.filter(
                m => data.active_downloads[m] && data.active_downloads[m].startsWith("error")
            );

            if (failed.length > 0) {
                return false;
            }

            if (stillDownloading.length === 0) {
                return true;
            }

            updateNotification(stillDownloading, models.length);
        } catch (e) {
            console.warn("Status poll failed:", e);
        }
    }

    return false;
}

let notificationEl = null;

function showDownloadNotification(models) {
    if (notificationEl) {
        notificationEl.remove();
    }

    notificationEl = document.createElement("div");
    notificationEl.id = "auto-model-download-notification";
    notificationEl.style.cssText = `
        position: fixed;
        top: 20px;
        left: 50%;
        transform: translateX(-50%);
        background: #1a1a2e;
        color: #e0e0e0;
        padding: 16px 24px;
        border-radius: 8px;
        border: 1px solid #4a4a6a;
        box-shadow: 0 4px 12px rgba(0,0,0,0.5);
        z-index: 10000;
        font-family: sans-serif;
        font-size: 14px;
        min-width: 300px;
        text-align: center;
    `;
    notificationEl.innerHTML = `
        <div style="font-weight: bold; margin-bottom: 8px;">Downloading Missing Models</div>
        <div class="download-status">${models.length} model(s) downloading...</div>
        <div style="margin-top: 8px; font-size: 12px; color: #888;">
            Workflow will execute automatically when ready
        </div>
        <div style="margin-top: 12px; height: 4px; background: #333; border-radius: 2px; overflow: hidden;">
            <div class="download-progress" style="height: 100%; background: #4CAF50; width: 0%; transition: width 0.5s;"></div>
        </div>
    `;
    document.body.appendChild(notificationEl);
}

function updateNotification(remaining, total) {
    if (!notificationEl) return;
    const done = total - remaining.length;
    const pct = Math.round((done / total) * 100);
    const status = notificationEl.querySelector(".download-status");
    const progress = notificationEl.querySelector(".download-progress");
    if (status) status.textContent = `${done}/${total} models ready (${remaining.length} downloading...)`;
    if (progress) progress.style.width = `${pct}%`;
}

function hideDownloadNotification() {
    if (notificationEl) {
        notificationEl.remove();
        notificationEl = null;
    }
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}
