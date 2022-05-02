#!/usr/bin/env -S node -r esm

// This file is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// For a full copy of the GNU General Public License
// see <http://www.gnu.org/licenses/>.

const jsonschema = require('jsonschema');
const mathjax_full = require("mathjax-full");
const readline = require('readline');
const process = require("process");

// Remove duplicate items from array.
function removeDuplicates(arr) {
    return arr.filter((item, index) => arr.indexOf(item) === index);
}

// JSON communication version.
const VERSION = 4;

// JSON communication schema.
const SCHEMA = {
    "type": "object",
    "properties": {
        "version": {
            "type": "number",
            "enum": [VERSION]
        },
        "id": { "type": "number" },
        "em": { "type": "number" },
        "ex": { "type": "number" },
        "containerWidth": { "type": "number" },
        "lineWidth": { "type": "number" },
        "payload": { "type": "string" },
        "inline": { "type": "bool" },
        "from": {
            "type": "string",
            "enum": ["tex", "mathml", "asciimath"]
        },
        "to": {
            "type": "string",
            "enum": ["svg"]
        }
    },
    required: ["id", "em", "ex", "containerWidth", "lineWidth", "payload", "inline", "from", "to"],
    additionalProperties: false
};

// Default MathJax configuration. Parts of it to be overwritten by program arguments.
var CONFIG = {
    loader: {
        load: ["input/tex-full", "input/mml", "input/asciimath", "output/svg"]
    },
    tex: {
        // http://docs.mathjax.org/en/latest/options/input/tex.html
        packages: ["base",
            "require",
            "newcommand",
            "configmacros"],
        processEscapes: true,
        processRefs: true,
        processEnvironments: true,
        digits: `/^(?:[0-9]+(?:\{,\}[0-9]*)?|\{,\}[0-9]+)/`,
        tags: "none",
        tagSide: 'right',
        useLabelIds: true,
        maxBuffer: 50 * 1024, // 10 times the reasonable amount
        // http://docs.mathjax.org/en/latest/input/tex/extensions/configmacros.html
        macros: {
        },
        environments: {
        },
        formatError: (_, err) => { throw err; },
    },
    // http://docs.mathjax.org/en/latest/options/output/svg.html#svg-options
    svg: {
        scale: 1,
        minScale: .5,
        mtextInheritFont: false,
        merrorInheritFont: false,
        mathmlSpacing: false,
        skipAttributes: {},
        exFactor: .5,
        displayAlign: 'center',
        displayIndent: '0',
        fontCache: 'none',
        localID: null,
        internalSpeechTitles: false,
        titleID: 0,
    },
    // https://docs.mathjax.org/en/latest/options/startup/startup.html#startup-options
    startup: {
        typeset: false,
    },
};

// Default configuration for tex packages. These will only be added to config is package is in packages list.
// May be overwritten by program arguments.
var TEX_PACKAGES_CONFIG = {
    // http://docs.mathjax.org/en/latest/input/tex/extensions/ams.html#tex-ams-options
    ams: {
        multlineWidth: "90%",
        multlineIndent: "1em",
    },
    // http://docs.mathjax.org/en/latest/input/tex/extensions/amscd.html#tex-amscd-options
    amscd: {
        colspace: '5pt',
        rowspace: '5pt',
        harrowsize: '2.75em',
        varrowsize: '1.75em',
        hideHorizontalLabels: false
    },
    // http://docs.mathjax.org/en/latest/input/tex/extensions/autoload.html#tex-autoload-options
    autoload: {
        action: ['toggle', 'mathtip', 'texttip'],
        amscd: [[], ['CD']],
        bbox: ['bbox'],
        boldsymbol: ['boldsymbol'],
        braket: ['bra', 'ket', 'braket', 'set', 'Bra', 'Ket', 'Braket', 'Set', 'ketbra', 'Ketbra'],
        cancel: ['cancel', 'bcancel', 'xcancel', 'cancelto'],
        color: ['color', 'definecolor', 'textcolor', 'colorbox', 'fcolorbox'],
        enclose: ['enclose'],
        extpfeil: ['xtwoheadrightarrow', 'xtwoheadleftarrow', 'xmapsto',
            'xlongequal', 'xtofrom', 'Newextarrow'],
        html: ['href', 'class', 'style', 'cssId'],
        mhchem: ['ce', 'pu'],
        newcommand: ['newcommand', 'renewcommand', 'newenvironment', 'renewenvironment', 'def', 'let'],
        unicode: ['unicode'],
        upgreek: ['upalpha', 'upbeta', 'upchi', 'updelta', 'Updelta', 'upepsilon',
            'upeta', 'upgamma', 'Upgamma', 'upiota', 'upkappa', 'uplambda',
            'Uplambda', 'upmu', 'upnu', 'upomega', 'Upomega', 'upomicron',
            'upphi', 'Upphi', 'uppi', 'Uppi', 'uppsi', 'Uppsi', 'uprho',
            'upsigma', 'Upsigma', 'uptau', 'uptheta', 'Uptheta', 'upupsilon',
            'Upupsilon', 'upvarepsilon', 'upvarphi', 'upvarpi', 'upvarrho',
            'upvarsigma', 'upvartheta', 'upxi', 'Upxi', 'upzeta'],
        verb: ['verb'],
    },
    // http://docs.mathjax.org/en/latest/input/tex/extensions/physics.html
    physics: {
        italicdiff: false,
        arrowdel: false
    }
};

process.argv.slice(2).forEach(arg => {
    try {
        let arg_parsed = JSON.parse(arg);
        let key = Object.keys(arg_parsed)[0];
        switch (key) {
            case "tex":
            case "loader":
            case "svg":
                if (CONFIG[key] == undefined) {
                    CONFIG[key] = {};
                }
                Object.assign(CONFIG[key], arg_parsed[key]);
                console.error(`applied section ${key}`);
                break;
            case "tex/macros":
            case "tex/environments":
                let keyname = key.split("/")[1];
                if (CONFIG["tex"][keyname] == undefined) {
                    CONFIG["tex"][keyname] = {};
                }
                Object.assign(CONFIG["tex"][keyname], arg_parsed[key]);
                console.error(`applied section ${key}`);
                break;
            case "tex/packages":
                CONFIG["tex"]["packages"] = removeDuplicates(
                    CONFIG["tex"]["packages"]
                        .concat(arg_parsed["tex/packages"]["tex/packages/list"])
                        .filter(x => x != undefined));
                Object.keys(arg_parsed["tex/packages"]).filter((x) => x != "tex/packages/list").
                    forEach(
                        (package) => {
                            Object.assign(TEX_PACKAGES_CONFIG[package],
                                arg_parsed["tex/packages"][package]);
                        }
                    );
                console.error(`preloaded packages list: ${CONFIG["tex"]["packages"]}`);
                CONFIG["tex"]["packages"].forEach(
                    (package) => {
                        // assign package options only if it is preloaded
                        if (TEX_PACKAGES_CONFIG[package] != undefined) {
                            if (CONFIG["tex"][package] == undefined) {
                                CONFIG["tex"][package] = {};
                            }
                            Object.assign(CONFIG["tex"][package], TEX_PACKAGES_CONFIG[package]);
                        }
                    }
                );
                break;
            default:
                console.error(`unknown option ${key}`);
                break;
        }
    } catch (error) {
        console.error(`error processing ${arg}: ${error}`);
    }
}
);

console.error(`mathjax configuration\n${JSON.stringify(CONFIG, null, 4)}`);

mathjax_full.init(CONFIG).then((MathJax) => {
    const adaptor = MathJax.startup.adaptor;

    readline.createInterface({
        input: process.stdin,
        output: process.stdout,
        terminal: false
    }).on('line',
        (line) => {
            try {
                let input = JSON.parse(line);
                jsonschema.validate(input, SCHEMA, { throwFirst: true });
                // https://docs.mathjax.org/en/latest/web/typeset.html#conversion-options
                MathJax[`${input.from}2${input.to}Promise`](input.payload, {
                    display: !input.inline,
                    em: input.em,
                    ex: input.ex,
                    containerWidth: input.containerWidth,
                    lineWidth: input.lineWidth,
                    scale: 1,
                }).then((math) => console.log(JSON.stringify({
                    id: input.id,
                    type: "svg",
                    payload: adaptor.innerHTML(math),
                }))).catch((error) => console.log(JSON.stringify({
                    id: input.id,
                    type: "error",
                    payload: error.message,
                })));
            } catch (E) {
                let output = { id: -1, type: "error" };
                if (E instanceof SyntaxError) {
                    output.payload = "JSON parse error";
                } else if (E instanceof jsonschema.ValidatorResultError) {
                    output.payload = "JSON schema mismatch. Check version compatibility";
                } else {
                    output.payload = "Unknown error";
                }
                console.log(JSON.stringify(output));
            }
        });
});
