#!/usr/bin/env node

var VERSION = 1;
var SCHEMA = {"type": "object",
              "properties": {
                  "id": { "type": "number" },
                  "version": { "type": "number" },
                  "data": { "type": "string" },
                  "inline": { "type": "boolean" }
              },
              required: ["id", "version", "data", "inline"],
              additionalProperties: false
             };

var validate = require('jsonschema');
var mjAPI = require("mathjax-node");
var readline = require('readline');

var rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false
});

mjAPI.config({displayErrors: false});
mjAPI.start();

rl.on('line',
      (line) => {
          var output = {"id": 0, "data": null, "error": null};
          var input = {};
          try {
              input = JSON.parse(line);
              validate.validate(input, SCHEMA, {throwFirst: true});
              output.id = input.id;

              if (input.version != VERSION) {
                  output.error = "Version mismatch";
                  console.log(JSON.stringify(output));
              } else {
                  mjAPI.typeset({
                      math: input.data,
                      format: input.inline ? "inline-TeX": "TeX",
                      svg:true,
                  }, function (data) {
                      if (!data.errors) {
                          output.data = data.svg;
                      } else {
                          output.error = data.errors;
                      }
                      console.log(JSON.stringify(output));
                  });
              }
          } catch(E) {
              if (E instanceof SyntaxError) {
                  output.error = "JSON parse error";
              } else if (E instanceof validate.ValidatorResultError) {
                  output.error = "Schema mismatch";
              } else {
                  output.error = "Unknown error";
              }
              console.log(JSON.stringify(output));
          }
      });
