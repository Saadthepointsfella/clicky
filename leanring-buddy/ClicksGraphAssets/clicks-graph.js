const AXIS_COLOR = { thinking: "#5b6e8c", designing: "#7a9468", doing: "#c08a3e", unsorted: "#a8a49a" };
const AXIS_TINT = { thinking: "#f3f6fb", designing: "#f3f8ef", doing: "#fdf8ee", unsorted: "#fbfaf6" };

const overlays = document.getElementById("node-overlays");
const emptyState = document.getElementById("empty-state");
let cy;
let ALL_NODES = [];
let ALL_EDGES = [];
let ACTIVE = "all";
let SEARCH = "";

function axisOf(node) {
  return node.axis && AXIS_COLOR[node.axis] ? node.axis : "unsorted";
}

function esc(value) {
  return String(value ?? "").replace(/[&<>"]/g, character => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "\"": "&quot;"
  }[character]));
}

function normalizePayload(payload) {
  const nodes = Array.isArray(payload?.nodes) ? payload.nodes : [];
  const edges = Array.isArray(payload?.edges) ? payload.edges : [];

  return {
    nodes: nodes.map(node => ({
      id: String(node.id ?? ""),
      caption: String(node.caption ?? ""),
      learning: String(node.learning ?? ""),
      sourceApp: String(node.sourceApp ?? "unknown"),
      axis: node.axis || null
    })).filter(node => node.id.length > 0),
    edges: edges.map(edge => ({
      id: String(edge.id ?? `${edge.source ?? edge.sourceNodeId}_${edge.target ?? edge.targetNodeId}`),
      source: String(edge.source ?? edge.sourceNodeId ?? ""),
      target: String(edge.target ?? edge.targetNodeId ?? ""),
      reason: String(edge.reason ?? edge.label ?? "")
    })).filter(edge => edge.source.length > 0 && edge.target.length > 0)
  };
}

window.renderClicksGraph = function(payload) {
  const normalizedPayload = normalizePayload(payload);
  ALL_NODES = normalizedPayload.nodes;
  ALL_EDGES = normalizedPayload.edges;

  emptyState.classList.toggle("hidden", ALL_NODES.length !== 0);
  overlays.innerHTML = "";
  if (cy) {
    cy.destroy();
    cy = null;
  }

  const counts = { all: ALL_NODES.length, thinking: 0, designing: 0, doing: 0, unsorted: 0 };
  ALL_NODES.forEach(node => counts[axisOf(node)]++);

  const rows = [
    ["all", "#a8a49a"],
    ["thinking", AXIS_COLOR.thinking],
    ["designing", AXIS_COLOR.designing],
    ["doing", AXIS_COLOR.doing],
    ["unsorted", AXIS_COLOR.unsorted]
  ];

  document.getElementById("axes").innerHTML = rows.map(([axis, color]) => `
    <div class="flex items-center justify-between cursor-pointer axis-row ${axis === ACTIVE ? "font-semibold" : ""}" data-axis="${axis}">
      <div class="flex items-center gap-3">
        <div class="axis-dot" style="background:${color}"></div>
        <span class="font-headline-md text-lg ${axis === ACTIVE ? "text-on-surface" : "text-on-surface-variant"}">${axis}</span>
      </div>
      <span class="font-pixel text-sm text-outline-variant">${counts[axis]}</span>
    </div>`).join("");

  document.querySelectorAll(".axis-row").forEach(row => {
    row.onclick = () => {
      ACTIVE = row.dataset.axis;
      build();
    };
  });

  const sourceMap = {};
  ALL_NODES.forEach(node => {
    const sourceApp = node.sourceApp || "unknown";
    sourceMap[sourceApp] = (sourceMap[sourceApp] || 0) + 1;
  });

  document.getElementById("src-chips").innerHTML = Object.entries(sourceMap)
    .sort((firstEntry, secondEntry) => secondEntry[1] - firstEntry[1])
    .map(([sourceApp, count]) => `<span class="source-chip">${esc(sourceApp)} <span class="source-count">${count}</span></span>`)
    .join("");

  build();
};

window.renderClicks = window.renderClicksGraph;

function build() {
  const visibleNodes = ALL_NODES.filter(node => {
    if (ACTIVE !== "all" && axisOf(node) !== ACTIVE) return false;
    if (SEARCH) {
      const haystack = `${node.caption || ""} ${node.learning || ""} ${node.sourceApp || ""}`.toLowerCase();
      if (!haystack.includes(SEARCH)) return false;
    }
    return true;
  });

  const visibleNodeIds = new Set(visibleNodes.map(node => node.id));
  const visibleEdges = ALL_EDGES.filter(edge => visibleNodeIds.has(edge.source) && visibleNodeIds.has(edge.target));

  const elements = [
    ...visibleNodes.map(node => ({ data: { id: node.id, axis: axisOf(node) } })),
    ...visibleEdges.map(edge => ({ data: { id: edge.id || `${edge.source}_${edge.target}`, source: edge.source, target: edge.target, reason: edge.reason || "" } }))
  ];

  if (cy) cy.destroy();
  cy = cytoscape({
    container: document.getElementById("cy"),
    elements,
    style: [
      { selector: "node", style: { "width": 248, "height": 150, "background-opacity": 0, "border-width": 0 } },
      { selector: "edge", style: { "width": 1.4, "line-color": "#8a8780", "opacity": 0.45, "curve-style": "bezier", "target-arrow-shape": "none" } },
      { selector: "edge:selected", style: { "line-color": "#5f7a5c", "opacity": 1, "width": 2 } }
    ],
    layout: { name: "preset" },
    minZoom: 0.4,
    maxZoom: 1.3
  });

  const anchor = { thinking: [-520, -340], designing: [520, -340], doing: [0, 420], unsorted: [0, 40] };
  const zoneCount = {};
  cy.nodes().forEach(node => {
    const visibleNode = visibleNodes.find(candidateNode => candidateNode.id === node.id());
    const axis = axisOf(visibleNode);
    const axisAnchor = anchor[axis];
    const zoneIndex = (zoneCount[axis] = (zoneCount[axis] || 0) + 1) - 1;
    const column = zoneIndex % 2;
    const row = Math.floor(zoneIndex / 2);
    node.position({
      x: axisAnchor[0] + column * 270 - 135 + (Math.random() * 24 - 12),
      y: axisAnchor[1] + row * 180 - 60 + (Math.random() * 24 - 12)
    });
  });

  overlays.innerHTML = "";
  visibleNodes.forEach(node => {
    const axis = axisOf(node);
    const element = document.createElement("div");
    element.id = `hn-${node.id}`;
    element.className = "html-node index-card p-5 flex flex-col gap-2-5 rounded-sm";
    element.style.backgroundColor = AXIS_TINT[axis];
    element.style.transform = `rotate(${(Math.random() * 3 - 1.5).toFixed(2)}deg)`;
    element.innerHTML = `
      <span class="font-pixel text-10 tracking-widest uppercase" style="color:${AXIS_COLOR[axis]}">${esc(node.sourceApp || "unknown")} // ${axis}</span>
      <h3 class="font-headline-md text-lg text-on-surface card-ruled-line pb-1-5 leading-snug">${esc(node.caption || "untitled")}</h3>
      <p class="font-body-md text-sm text-on-surface-variant leading-relaxed">${esc((node.learning || "").slice(0, 120))}</p>`;
    overlays.appendChild(element);
  });

  const sync = () => {
    const pan = cy.pan();
    const zoom = cy.zoom();
    overlays.style.transform = `translate(${pan.x}px,${pan.y}px) scale(${zoom})`;
    cy.nodes().forEach(node => {
      const element = document.getElementById(`hn-${node.id()}`);
      if (element) {
        const position = node.position();
        element.style.left = `${position.x - 124}px`;
        element.style.top = `${position.y - 75}px`;
      }
    });
  };

  cy.on("render pan zoom", sync);
  sync();
  cy.fit(undefined, 100);
  if (cy.zoom() > 0.95) {
    cy.zoom(0.95);
  }
  cy.center();
  sync();

  cy.on("tap", "edge", event => {
    const reason = event.target.data("reason");
    if (reason) toast(`linked: ${reason}`);
  });

  document.getElementById("zoom-in").onclick = () => cy.animate({ zoom: cy.zoom() * 1.2, duration: 140 });
  document.getElementById("zoom-out").onclick = () => cy.animate({ zoom: cy.zoom() * 0.8, duration: 140 });
  document.getElementById("fit").onclick = () => cy.animate({ fit: { padding: 90 }, duration: 200 });
}

let toastTimer;
function toast(message) {
  const toastElement = document.getElementById("toast");
  toastElement.textContent = message;
  toastElement.style.opacity = "1";
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toastElement.style.opacity = "0";
  }, 2200);
}

document.getElementById("search").addEventListener("input", event => {
  SEARCH = event.target.value.trim().toLowerCase();
  build();
});

window.addEventListener("resize", () => {
  if (cy) cy.fit(undefined, 90);
});

window.renderClicksGraph({ nodes: [], edges: [] });
