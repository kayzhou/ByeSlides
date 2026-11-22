// Renders Markdown for reading mode. Loaded after markdown-it and DOMPurify.
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

// CommonMark plus the extensions supported by earlier versions of ByeSlides.
const markdown = markdownit("commonmark", {linkify: true})
    .enable(["table", "strikethrough", "linkify"])
    .use(taskLists)
    .use(tableAlignment);

const sanitizeOptions = {
    RETURN_DOM_FRAGMENT: true,
    ALLOWED_TAGS: ("a abbr b blockquote br caption cite code dd del details div dl dt em " +
        "figcaption figure h1 h2 h3 h4 h5 h6 hr i img input ins kbd li mark ol p pre q s samp small " +
        "span strong sub summary sup table tbody td th thead tfoot tr u ul var wbr").split(" "),
    ALLOWED_ATTR: ("href src alt title start reversed value align colspan rowspan scope open checked " +
        "disabled type class id name width height").split(" "),
    ALLOW_DATA_ATTR: false
};

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

const postProcessors = [restrictInputs, addHeadingIds, wrapTables];

function displayMarkdown(source) {
    const fragment = DOMPurify.sanitize(markdown.render(source), sanitizeOptions);
    for (const process of postProcessors) process(fragment);
    document.querySelector("main").replaceChildren(fragment);
}

// Same-page links scroll here. The app cancels every other link and opens it outside the page.
document.addEventListener("click", event => {
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
