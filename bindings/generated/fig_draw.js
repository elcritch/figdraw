var ffi = require('ffi-napi');
var Struct = require("ref-struct-napi");
var ArrayType = require('ref-array-napi');

var dll = {};

function FigDrawException(message) {
  this.message = message;
  this.name = 'FigDrawException';
}

function figDataDir(){
  result = dll.fig_draw_fig_data_dir()
  return result
}

function setFigDataDir(dir){
  dll.fig_draw_set_fig_data_dir(dir)
}

function figUiScale(){
  result = dll.fig_draw_fig_ui_scale()
  return result
}

function setFigUiScale(scale){
  dll.fig_draw_set_fig_ui_scale(scale)
}

function scaled(a){
  result = dll.fig_draw_scaled(a)
  return result
}

function descaled(a){
  result = dll.fig_draw_descaled(a)
  return result
}


var dllPath = ""
if(process.platform == "win32") {
  dllPath = __dirname + '/fig_draw.dll'
} else if (process.platform == "darwin") {
  dllPath = __dirname + '/libfig_draw.dylib'
} else {
  dllPath = __dirname + '/libfig_draw.so'
}

dll = ffi.Library(dllPath, {
  'fig_draw_fig_data_dir': ['string', []],
  'fig_draw_set_fig_data_dir': ['void', ['string']],
  'fig_draw_fig_ui_scale': ['float', []],
  'fig_draw_set_fig_ui_scale': ['void', ['float']],
  'fig_draw_scaled': ['float', ['float']],
  'fig_draw_descaled': ['float', ['float']],
});

exports.figDataDir = figDataDir
exports.setFigDataDir = setFigDataDir
exports.figUiScale = figUiScale
exports.setFigUiScale = setFigUiScale
exports.scaled = scaled
exports.descaled = descaled
