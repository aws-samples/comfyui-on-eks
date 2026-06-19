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
    if (widget.name && MODEL_EXTENSIONS.some(ext => widget.name.toLowerCase().includes("lora") || widget.name.toLowerCase().includes("ckpt") || widget.name.toLowerCase().includes("model"))) {
        return true;
    }
    return false;
}

function fixSubgraphModelDefaults(node) {
    if (!node.widgets) return;

    const subgraph = node.subgraph;
    const proxyWidgets = node.properties?.proxyWidgets;
    if (!subgraph && !proxyWidgets) return;

    for (let i = 0; i < node.widgets.length; i++) {
        const widget = node.widgets[i];

        let innerNodeId = null;
        let innerWidgetName = null;

        if (widget.sourceNodeId && widget.sourceWidgetName) {
            innerNodeId = widget.sourceNodeId;
            innerWidgetName = widget.sourceWidgetName;
        } else if (proxyWidgets && i < proxyWidgets.length) {
            [innerNodeId, innerWidgetName] = proxyWidgets[i];
        }

        if (!innerNodeId || !innerWidgetName) continue;
        if (!MODEL_WIDGET_TYPES.includes(innerWidgetName)) continue;

        let innerValue = null;

        if (subgraph) {
            const nodesById = subgraph._nodes_by_id || {};
            const innerNode = nodesById[innerNodeId] || nodesById[String(innerNodeId)];
            if (innerNode?.widgets) {
                const innerWidget = innerNode.widgets.find(w => w.name === innerWidgetName);
                if (innerWidget && typeof innerWidget.value === "string") {
                    innerValue = innerWidget.value;
                }
            }
        }

        if (!innerValue) {
            const defs = app.graph?.extra?.definitions?.subgraphs
                || app.graph?._extra_data?.definitions?.subgraphs || [];
            const sgDef = defs.find(sg => sg.id === node.type);
            if (sgDef) {
                const innerNodeDef = sgDef.nodes?.find(
                    n => String(n.id) === String(innerNodeId)
                );
                if (innerNodeDef?.widgets_values) {
                    const widgetIdx = getWidgetValueIndex(innerNodeDef.type, innerWidgetName);
                    const val = innerNodeDef.widgets_values[widgetIdx];
                    if (val && typeof val === "string") {
                        innerValue = val;
                    }
                }
            }
        }

        if (!innerValue || typeof innerValue !== "string") continue;
        if (!MODEL_EXTENSIONS.some(ext => innerValue.endsWith(ext))) continue;
        if (widget.value === innerValue) continue;

        if (!widget.options) widget.options = {};
        if (!widget.options.values) widget.options.values = [];
        if (!widget.options.values.includes(innerValue)) {
            widget.options.values.push(innerValue);
        }
        widget.value = innerValue;
    }
}

function getWidgetValueIndex(nodeType, widgetName) {
    const widgetOrder = {
        "UNETLoader": ["unet_name", "weight_dtype"],
        "CLIPLoader": ["clip_name", "type", "device"],
        "DualCLIPLoader": ["clip_name1", "clip_name2", "type"],
        "VAELoader": ["vae_name"],
        "LoraLoader": ["lora_name", "strength_model", "strength_clip"],
        "LoraLoaderModelOnly": ["lora_name", "strength_model"],
        "CheckpointLoaderSimple": ["ckpt_name"],
    };
    const order = widgetOrder[nodeType];
    if (order) return order.indexOf(widgetName);
    return 0;
}

function fixExpandedPromptFromSubgraphNodes(output) {
    const nodes = app.graph?._nodes || [];
    const subgraphNodes = nodes.filter(n => n.isSubgraphNode?.() && n.subgraph);
    if (subgraphNodes.length === 0) {
        console.log("[AMD] No subgraph nodes with live subgraphs found");
        return;
    }

    const widgetOrder = {
        "UNETLoader": ["unet_name", "weight_dtype"],
        "CLIPLoader": ["clip_name", "type", "device"],
        "DualCLIPLoader": ["clip_name1", "clip_name2", "type"],
        "VAELoader": ["vae_name"],
        "LoraLoader": ["lora_name", "strength_model", "strength_clip"],
        "LoraLoaderModelOnly": ["lora_name", "strength_model"],
        "CheckpointLoaderSimple": ["ckpt_name"],
    };

    let fixed = 0;
    for (const sgNode of subgraphNodes) {
        const sgId = String(sgNode.id);
        const innerNodes = sgNode.subgraph._nodes || [];

        for (const innerNode of innerNodes) {
            const classType = innerNode.type;
            const order = widgetOrder[classType];
            if (!order) continue;

            // The expanded prompt node ID is "sgId:innerNodeId"
            const expandedId = `${sgId}:${innerNode.id}`;
            const nodeData = output[expandedId];
            if (!nodeData) continue;

            const inputs = nodeData.inputs || {};
            const innerWidgets = innerNode.widgets || [];

            for (let i = 0; i < order.length; i++) {
                const fieldName = order[i];
                if (!MODEL_WIDGET_TYPES.includes(fieldName)) continue;

                // Get the inner widget's actual value
                const innerWidget = innerWidgets.find(w => w.name === fieldName);
                if (!innerWidget) continue;
                const intendedValue = innerWidget.value;
                if (!intendedValue || typeof intendedValue !== "string") continue;
                if (!MODEL_EXTENSIONS.some(ext => intendedValue.endsWith(ext))) continue;

                const currentValue = inputs[fieldName];
                if (currentValue === intendedValue) continue;

                console.log(`[AMD] Fixing ${classType} node ${expandedId}: ${fieldName} "${currentValue}" -> "${intendedValue}"`);
                inputs[fieldName] = intendedValue;
                fixed++;
            }
        }
    }
    console.log(`[AMD] fixExpandedPromptFromSubgraphNodes: fixed ${fixed} fields`);
}

function fixExpandedPromptFromDefinitions(output, workflow, liveDefs) {
    const defs = liveDefs && liveDefs.length > 0
        ? liveDefs
        : (workflow?.extra?.definitions?.subgraphs || []);
    console.log("[AMD] fixExpandedPrompt: defs count =", defs.length);

    if (defs.length === 0) {
        fixExpandedPromptByClassType(output);
        return;
    }

    const defNodeMap = new Map();
    for (const sg of defs) {
        for (const n of sg.nodes || []) {
            defNodeMap.set(String(n.id), n);
        }
    }

    const widgetOrder = {
        "UNETLoader": ["unet_name", "weight_dtype"],
        "CLIPLoader": ["clip_name", "type", "device"],
        "DualCLIPLoader": ["clip_name1", "clip_name2", "type"],
        "VAELoader": ["vae_name"],
        "LoraLoader": ["lora_name", "strength_model", "strength_clip"],
        "LoraLoaderModelOnly": ["lora_name", "strength_model"],
        "CheckpointLoaderSimple": ["ckpt_name"],
    };

    let fixed = 0;
    for (const [nodeId, nodeData] of Object.entries(output)) {
        const classType = nodeData.class_type;
        if (!classType) continue;
        const order = widgetOrder[classType];
        if (!order) continue;

        // Try matching nodeId directly, or strip prefix (e.g. "139:129" -> "129")
        let defNode = defNodeMap.get(nodeId);
        if (!defNode) {
            const colonIdx = nodeId.lastIndexOf(":");
            if (colonIdx >= 0) {
                defNode = defNodeMap.get(nodeId.substring(colonIdx + 1));
            }
        }
        if (!defNode || !defNode.widgets_values) continue;
        if (defNode.type !== classType) continue;

        const inputs = nodeData.inputs || {};
        for (let i = 0; i < order.length; i++) {
            const fieldName = order[i];
            if (!MODEL_WIDGET_TYPES.includes(fieldName)) continue;
            if (i >= defNode.widgets_values.length) continue;

            const intendedValue = defNode.widgets_values[i];
            if (!intendedValue || typeof intendedValue !== "string") continue;
            if (!MODEL_EXTENSIONS.some(ext => intendedValue.endsWith(ext))) continue;

            const currentValue = inputs[fieldName];
            if (currentValue === intendedValue) continue;
            if (typeof currentValue === "string") {
                console.log(`[AMD] Fixing ${classType} node ${nodeId}: ${fieldName} "${currentValue}" -> "${intendedValue}"`);
                inputs[fieldName] = intendedValue;
                fixed++;
            }
        }
    }
    console.log("[AMD] fixExpandedPrompt: fixed", fixed, "fields");
}

function fixExpandedPromptByClassType(output) {
    const modelLoaderNodes = {};
    for (const [nodeId, nodeData] of Object.entries(output)) {
        const ct = nodeData.class_type;
        if (ct === "UNETLoader" || ct === "CLIPLoader" || ct === "VAELoader" ||
            ct === "DualCLIPLoader" || ct === "LoraLoaderModelOnly" || ct === "CheckpointLoaderSimple") {
            if (!modelLoaderNodes[ct]) modelLoaderNodes[ct] = [];
            modelLoaderNodes[ct].push({ nodeId, inputs: nodeData.inputs || {} });
        }
    }
    console.log("[AMD] Model loader nodes found:", Object.keys(modelLoaderNodes).map(k => `${k}:${modelLoaderNodes[k].length}`));
}

function fixAllSubgraphModelDefaults() {
    const nodes = app.graph?._nodes || [];
    for (const node of nodes) {
        if (node.isSubgraphNode?.()) {
            fixSubgraphModelDefaults(node);
        }
    }
}

function injectMissingModelValues() {
    const injected = [];
    const nodes = app.graph._nodes || [];

    for (const node of nodes) {
        if (!node.widgets) continue;
        for (const widget of node.widgets) {
            if (!isModelWidget(widget)) continue;

            const options = widget.options?.values || [];

            if (widget.value === null || widget.value === undefined || widget.value === "None") {
                if (options.length === 0) {
                    if (!widget.options) widget.options = {};
                    if (!widget.options.values) widget.options.values = [];
                    widget.options.values.push("None");
                    widget.value = "None";
                    injected.push({ node: node.id, widget: widget.name, value: "None" });
                }
                continue;
            }

            if (typeof widget.value !== "string") continue;

            if (options.length === 0 || !options.includes(widget.value)) {
                if (!widget.options) widget.options = {};
                if (!widget.options.values) widget.options.values = [];
                widget.options.values.push(widget.value);
                injected.push({ node: node.id, widget: widget.name, value: widget.value });
            }
        }
    }
    return injected;
}

app.registerExtension({
    name: "comfyui-auto-model-downloader",

    afterConfigureGraph() {
        fixAllSubgraphModelDefaults();
    },

    nodeCreated(node) {
        if (node.isSubgraphNode?.()) {
            setTimeout(() => fixSubgraphModelDefaults(node), 0);
        }
    },

    async setup() {
        const originalQueuePrompt = api.queuePrompt.bind(api);

        const originalGraphToPrompt = app.graphToPrompt.bind(app);
        app.graphToPrompt = async function() {
            fixAllSubgraphModelDefaults();
            injectMissingModelValues();
            const result = await originalGraphToPrompt();
            const defs = app.graph?.extra?.definitions;
            if (defs && result.workflow) {
                if (!result.workflow.extra) result.workflow.extra = {};
                if (!result.workflow.extra.definitions) {
                    result.workflow.extra.definitions = defs;
                }
            }
            return result;
        };

        api.queuePrompt = async function(number, { output, workflow }) {
            fixExpandedPromptFromSubgraphNodes(output);
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

        const dialog = document.createElement("div");
        dialog.style.cssText = `
            background: #1a1a2e; color: #e0e0e0; padding: 24px;
            border-radius: 12px; border: 1px solid #4a4a6a;
            box-shadow: 0 8px 24px rgba(0,0,0,0.8);
            max-width: 500px; width: 90%; font-family: sans-serif;
        `;

        const title = document.createElement("div");
        title.style.cssText = "font-size: 16px; font-weight: bold; margin-bottom: 12px;";
        title.textContent = "Bedrock Alternatives Available";
        dialog.appendChild(title);

        const subtitle = document.createElement("div");
        subtitle.style.cssText = "font-size: 13px; color: #aaa; margin-bottom: 16px;";
        subtitle.textContent = `${Object.keys(alternatives).length} missing model(s) can be replaced with Amazon Bedrock — instant access, no download required.`;
        dialog.appendChild(subtitle);

        const altContainer = document.createElement("div");
        altContainer.style.cssText = "max-height: 200px; overflow-y: auto; margin-bottom: 16px;";
        Object.entries(alternatives).forEach(([model, info]) => {
            const row = document.createElement("div");
            row.style.cssText = "margin: 4px 0; padding: 8px; background: #2a2a4a; border-radius: 4px; font-size: 12px;";
            const nodeName = document.createElement("span");
            nodeName.style.cssText = "color: #4CAF50; font-weight: bold;";
            nodeName.textContent = info.node;
            const desc = document.createElement("span");
            desc.style.cssText = "color: #888; margin-left: 8px;";
            desc.textContent = info.description;
            row.appendChild(nodeName);
            row.appendChild(desc);
            altContainer.appendChild(row);
        });
        dialog.appendChild(altContainer);

        const btnContainer = document.createElement("div");
        btnContainer.style.cssText = "display: flex; gap: 12px; justify-content: flex-end;";
        const downloadBtn = document.createElement("button");
        downloadBtn.id = "amd-btn-download";
        downloadBtn.style.cssText = "padding: 8px 16px; border-radius: 6px; border: 1px solid #555; background: #333; color: #e0e0e0; cursor: pointer; font-size: 13px;";
        downloadBtn.textContent = "Download Models Instead";
        const bedrockBtn = document.createElement("button");
        bedrockBtn.id = "amd-btn-bedrock";
        bedrockBtn.style.cssText = "padding: 8px 16px; border-radius: 6px; border: none; background: #4CAF50; color: white; cursor: pointer; font-size: 13px; font-weight: bold;";
        bedrockBtn.textContent = "Use Bedrock (Instant)";
        btnContainer.appendChild(downloadBtn);
        btnContainer.appendChild(bedrockBtn);
        dialog.appendChild(btnContainer);

        const tip = document.createElement("div");
        tip.style.cssText = "margin-top: 12px; font-size: 11px; color: #666;";
        tip.textContent = "Tip: Add Bedrock nodes to your workflow for cloud-powered inference without local GPU models.";
        dialog.appendChild(tip);

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
    const ntTitle = document.createElement("div");
    ntTitle.style.cssText = "font-weight: bold; margin-bottom: 8px;";
    ntTitle.textContent = "Downloading Missing Models";
    notificationEl.appendChild(ntTitle);

    const ntStatus = document.createElement("div");
    ntStatus.className = "download-status";
    ntStatus.textContent = `${models.length} model(s) downloading...`;
    notificationEl.appendChild(ntStatus);

    const ntHint = document.createElement("div");
    ntHint.style.cssText = "margin-top: 8px; font-size: 12px; color: #888;";
    ntHint.textContent = "Workflow will execute automatically when ready";
    notificationEl.appendChild(ntHint);

    const ntProgressWrap = document.createElement("div");
    ntProgressWrap.style.cssText = "margin-top: 12px; height: 4px; background: #333; border-radius: 2px; overflow: hidden;";
    const ntProgressBar = document.createElement("div");
    ntProgressBar.className = "download-progress";
    ntProgressBar.style.cssText = "height: 100%; background: #4CAF50; width: 0%; transition: width 0.5s;";
    ntProgressWrap.appendChild(ntProgressBar);
    notificationEl.appendChild(ntProgressWrap);
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
