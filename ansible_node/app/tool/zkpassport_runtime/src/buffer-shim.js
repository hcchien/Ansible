// esbuild injects this binding into every bundled module that references the
// Node-style free `Buffer` identifier. A runtime global assignment is not
// sufficient in WKWebView because dependency modules can execute in a
// different initialization scope.
export { Buffer } from "buffer"
