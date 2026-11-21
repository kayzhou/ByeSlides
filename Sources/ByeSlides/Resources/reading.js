// CommonMark plus the extensions supported by earlier versions of ByeSlides.
const markdown = markdownit("commonmark", {linkify: true}).enable(["table", "strikethrough", "linkify"]);

markdown.core.ruler.after("inline", "task_lists", state => {
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
markdown.renderer.rules.task_checkbox = (tokens, i) =>
    '<input type="checkbox" disabled' + (tokens[i].meta.checked ? ' checked' : '') + '>';

// Preserve table alignment without accepting arbitrary document CSS.
for (const name of ["th_open", "td_open"]) {
    markdown.renderer.rules[name] = (tokens, i, options, env, renderer) => {
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

function displayMarkdown(source) {
    const main = document.querySelector("main");
    const fragment = DOMPurify.sanitize(markdown.render(source), {
        RETURN_DOM_FRAGMENT: true,
        ALLOWED_TAGS: ("a abbr b blockquote br caption cite code dd del details div dl dt em " +
            "figcaption figure h1 h2 h3 h4 h5 h6 hr i img input ins kbd li mark ol p pre q s samp small " +
            "span strong sub summary sup table tbody td th thead tfoot tr u ul var wbr").split(" "),
        ALLOWED_ATTR: ("href src alt title start reversed value align colspan rowspan scope open checked " +
            "disabled type class id name width height").split(" "),
        ALLOW_DATA_ATTR: false
    });
    for (const input of fragment.querySelectorAll("input")) {
        if (input.type === "checkbox") input.disabled = true;
        else input.remove();
    }
    const ids = new Set([...fragment.querySelectorAll("[id]")].map(node => node.id));
    for (const heading of fragment.querySelectorAll("h1,h2,h3,h4,h5,h6")) {
        if (heading.id) continue;
        const base = heading.textContent.toLowerCase().trim().replace(/[^\p{L}\p{M}\p{N}_\s-]/gu, "").replace(/\s+/g, "-") || "section";
        let id = base;
        for (let n = 1; ids.has(id); n++) id = base + "-" + n;
        heading.id = id;
        ids.add(id);
    }
    for (const table of fragment.querySelectorAll("table")) {
        const wrapper = document.createElement("div");
        wrapper.className = "table-scroll";
        table.replaceWith(wrapper);
        wrapper.append(table);
    }
    main.replaceChildren(fragment);
    main.addEventListener("click", event => {
        const href = event.target.closest("a")?.getAttribute("href");
        if (!href?.startsWith("#")) return;
        event.preventDefault();
        try {
            const id = decodeURIComponent(href.slice(1));
            const target = document.getElementById(id) || document.getElementsByName(id)[0];
            if (id === "") window.scrollTo(0, 0);
            else target?.scrollIntoView();
        } catch { /* A malformed fragment has no matching anchor. */ }
    });
}
