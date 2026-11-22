// Renders Markdown for reading mode, printing and Quick Look. Loaded after markdown-it and DOMPurify.
// To support more syntax, add a markdown-it plugin and pass it to `.use()` below.
// To adjust the rendered page, add a function to `postProcessors`.

// Turns `[ ]` or `[x]` at the start of a list item into a read-only checkbox.
function taskLists(md) {
    md.core.ruler.after("inline", "task_lists", state => {
        const tokens = state.tokens;
        for (let i = 2; i < tokens.length; i++) {
            const token = tokens[i];
            if (token.type !== "inline" || tokens[i - 1].type !== "paragraph_open" ||
                tokens[i - 2].type !== "list_item_open") continue;
            const marker = /^\[([ xX])\](?=\s|$)/.exec(token.content);
            const first = token.children[0];
            if (!marker || first?.type !== "text" || !first.content.startsWith(marker[0])) continue;
            first.content = first.content.slice(3);
            const box = new state.Token("task_checkbox", "input", 0);
            box.meta = {checked: marker[1] !== " "};
            token.children.unshift(box);
            tokens[i - 2].attrJoin("class", "task-item");
        }
    });
    md.renderer.rules.task_checkbox = (tokens, i) =>
        '<input type="checkbox" disabled' + (tokens[i].meta.checked ? ' checked' : '') + '>';
}

// Keeps table column alignment as an `align` attribute so no document CSS reaches the page.
function tableAlignment(md) {
    for (const name of ["th_open", "td_open"]) {
        md.renderer.rules[name] = (tokens, i, options, env, renderer) => {
            const token = tokens[i];
            const style = token.attrGet("style");
            if (style) {
                const align = /^text-align:(left|center|right)$/.exec(style);
                token.attrs.splice(token.attrIndex("style"), 1);
                if (align) token.attrSet("align", align[1]);
            }
            return renderer.renderToken(tokens, i, options);
        };
    }
}

// Marks each block with the zero-based source lines it came from, [start, end),
// so switching between editing and reading keeps the same passage in view.
function sourceLines(md) {
    md.core.ruler.push("source_lines", state => {
        for (const token of state.tokens) {
            if (!token.map || token.nesting < 0 || token.type === "inline") continue;
            token.attrSet("data-source-line", String(token.map[0]));
            token.attrSet("data-source-end", String(token.map[1]));
        }
    });
}

// CommonMark plus the extensions supported by earlier versions of ByeSlides.
const markdown = markdownit("commonmark", {linkify: true})
    .enable(["table", "strikethrough", "linkify"])
    .use(taskLists)
    .use(tableAlignment)
    .use(sourceLines);

const sanitizeOptions = {
    RETURN_DOM_FRAGMENT: true,
    ALLOWED_TAGS: ("a abbr b blockquote br caption cite code dd del details div dl dt em " +
        "figcaption figure h1 h2 h3 h4 h5 h6 hr i img input ins kbd li mark ol p pre q s samp small " +
        "span strong sub summary sup table tbody td th thead tfoot tr u ul var wbr").split(" "),
    ALLOWED_ATTR: ("href src alt title start reversed value align colspan rowspan scope open checked " +
        "disabled type class id name width height data-source-line data-source-end").split(" "),
    ALLOW_DATA_ATTR: false
};

// Sends a message to the app. Quick Look has no handler, so nothing is sent there.
function postToApp(message) {
    window.webkit?.messageHandlers?.reading?.postMessage(message);
}

// Raw HTML in the document may contain inputs; only read-only checkboxes survive.
function restrictInputs(root) {
    for (const input of root.querySelectorAll("input")) {
        if (input.type === "checkbox") input.disabled = true;
        else input.remove();
    }
}

// Gives each heading a unique id so `#section` links can reach it.
function addHeadingIds(root) {
    const ids = new Set([...root.querySelectorAll("[id]")].map(node => node.id));
    for (const heading of root.querySelectorAll("h1,h2,h3,h4,h5,h6")) {
        if (heading.id) continue;
        const base = heading.textContent.toLowerCase().trim()
            .replace(/[^\p{L}\p{M}\p{N}_\s-]/gu, "").replace(/\s+/g, "-") || "section";
        let id = base;
        for (let n = 1; ids.has(id); n++) id = base + "-" + n;
        heading.id = id;
        ids.add(id);
    }
}

// Lets wide tables scroll sideways on their own.
function wrapTables(root) {
    for (const table of root.querySelectorAll("table")) {
        const wrapper = document.createElement("div");
        wrapper.className = "table-scroll";
        table.replaceWith(wrapper);
        wrapper.append(table);
    }
}

// Loading a remote image tells its server that the document was opened, so remote images
// stay as placeholders until the reader chooses to load them. The page's CSP blocks them too.
function holdRemoteImages(root, options) {
    if (options.remoteImages) return;
    const remote = [...root.querySelectorAll("img")].filter(img => /^https?:/i.test(img.getAttribute("src") ?? ""));
    for (const img of remote) {
        const placeholder = document.createElement("span");
        placeholder.className = "blocked-image";
        placeholder.textContent = img.getAttribute("alt") || "远程图片";
        placeholder.title = img.getAttribute("src");
        img.replaceWith(placeholder);
    }
    if (remote.length === 0) return;
    const notice = document.createElement("p");
    notice.className = "remote-notice";
    notice.append(`为保护隐私，未载入 ${remote.length} 张远程图片。`);
    if (options.offerRemoteImages && window.webkit?.messageHandlers?.reading) {
        const button = document.createElement("button");
        button.type = "button";
        button.textContent = "载入";
        notice.append(button);
    }
    root.prepend(notice);
}

// A single leading slash denotes the document folder. Resolve it under the same
// base path as other local references so the app can still check folder boundaries.
function keepLocalPathsInDocument(root) {
    for (const element of root.querySelectorAll("a[href], img[src]")) {
        const attribute = element.tagName === "A" ? "href" : "src";
        const reference = element.getAttribute(attribute).trim();
        if (/^(?:#|\/\/|[a-z][a-z0-9+.-]*:)/i.test(reference)) continue;
        let depth = 0;
        for (const segment of reference.split(/[?#]/, 1)[0].split("/")) {
            const component = segment.replace(/%2e/ig, ".");
            if (!component || component === ".") continue;
            depth += component === ".." ? -1 : 1;
            if (depth >= 0) continue;
            element.removeAttribute(attribute);
            break;
        }
        if (depth >= 0 && reference.startsWith("/")) element.setAttribute(attribute, "." + reference);
    }
}

const postProcessors = [restrictInputs, addHeadingIds, wrapTables, holdRemoteImages, keepLocalPathsInDocument];

let sourceBlocks = [];

function displayMarkdown(source, options = {}) {
    const fragment = DOMPurify.sanitize(markdown.render(source), sanitizeOptions);
    for (const process of postProcessors) process(fragment, options);
    document.querySelector("main").replaceChildren(fragment);
    sourceBlocks = [...document.querySelectorAll("[data-source-line]")].map(element => ({
        element, start: Number(element.dataset.sourceLine), end: Number(element.dataset.sourceEnd)
    }));
    restoreSourceLine(options.line ?? 0);
}

// MARK: Keeping the same passage in view

// The source line at the top of the viewport: the last block starting above it, plus however
// far into that block the reader has scrolled.
function topSourceLine() {
    let line = 0;
    for (const {element, start, end} of sourceBlocks) {
        const box = element.getBoundingClientRect();
        if (box.top > 1) break;
        // A block a pixel below the top has not been scrolled into yet.
        const progress = box.height > 0 ? Math.max(0, Math.min(1, -box.top / box.height)) : 0;
        line = Math.min(end - 1, start + Math.floor(progress * (end - start)));
    }
    return Math.max(0, line);
}

function scrollToSourceLine(line) {
    let target = null;
    for (const block of sourceBlocks) {
        if (block.start > line) break;
        target = block;
    }
    if (!target || line <= 0) return window.scrollTo(0, 0);
    const box = target.element.getBoundingClientRect();
    const progress = Math.min(1, (line - target.start) / Math.max(1, target.end - target.start));
    window.scrollTo(0, window.scrollY + box.top + progress * box.height);
}

// Keep the same point within the visible Markdown block when a font size reflows the page.
function withReadingPosition(update) {
    if (window.scrollY === 0) return update();
    let anchor;
    for (const {element} of sourceBlocks) {
        const box = element.getBoundingClientRect();
        if (box.top > 0) break;
        anchor = {element, top: box.top, height: box.height};
    }
    update();
    if (anchor) {
        const box = anchor.element.getBoundingClientRect();
        const scale = anchor.height > 0 ? box.height / anchor.height : 1;
        window.scrollBy(0, box.top - anchor.top * scale);
    }
}

// Fonts and images change the layout after the first paint, so the position is applied again
// once they arrive, unless the reader has started scrolling by then.
let readerHasScrolled = false;
let restoredScrollY = 0;
function restoreSourceLine(line) {
    readerHasScrolled = false;
    restoredScrollY = window.scrollY;
    if (line <= 0) return;
    const apply = () => {
        if (readerHasScrolled) return;
        scrollToSourceLine(line);
        restoredScrollY = window.scrollY;
    };
    apply();
    document.fonts.ready.then(apply);
    window.addEventListener("load", apply, {once: true});
}
for (const type of ["wheel", "keydown", "mousedown", "touchstart"]) {
    window.addEventListener(type, () => { readerHasScrolled = true; }, {passive: true, capture: true});
}

// Reported at most every 50 ms. A timer rather than requestAnimationFrame, which never fires
// in a web view that isn't on screen.
let reportedLine = -1;
let reportedRestoration = false;
let reportTimer = null;
window.addEventListener("scroll", () => {
    reportTimer ??= setTimeout(() => {
        reportTimer = null;
        const line = topSourceLine();
        const restored = !readerHasScrolled && Math.abs(window.scrollY - restoredScrollY) < 1;
        if (!restored) readerHasScrolled = true;
        if (line !== reportedLine || restored !== reportedRestoration) {
            reportedLine = line;
            reportedRestoration = restored;
            postToApp({type: "scroll", line, restored});
        }
    }, 50);
}, {passive: true});

// Same-page links scroll here. The app handles links to other documents and websites.
document.addEventListener("click", event => {
    if (event.target.closest?.(".remote-notice button")) return postToApp({type: "loadRemoteImages"});
    const href = event.target.closest?.("a")?.getAttribute("href");
    if (!href?.startsWith("#")) return;
    event.preventDefault();
    try {
        const id = decodeURIComponent(href.slice(1));
        const target = document.getElementById(id) || document.getElementsByName(id)[0];
        if (id === "") window.scrollTo(0, 0);
        else target?.scrollIntoView();
    } catch { /* A malformed fragment has no matching anchor. */ }
});
