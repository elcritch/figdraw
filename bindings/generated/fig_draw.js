var ffi = require('ffi-napi');
var Struct = require("ref-struct-napi");
var ArrayType = require('ref-array-napi');

var dll = {};

function FigDrawException(message) {
  this.message = message;
  this.name = 'FigDrawException';
}

const FigKind = 'int8'

Fig = Struct({'nimRef': 'uint64'});
Fig.prototype.isNull = function(){
  return this.nimRef == 0;
};
Fig.prototype.isEqual = function(other){
  return this.nimRef == other.nimRef;
};
Fig.prototype.unref = function(){
  return dll.fig_draw_fig_unref(this)
};
function newFig(){
  var result = dll.fig_draw_new_fig()
  const registry = new FinalizationRegistry(function(obj) {
    console.log("js unref")
    obj.unref()
  });
  registry.register(result, null);
  return result
}

Fig.prototype.copy = function(){
  result = dll.fig_draw_fig_copy(this)
  return result
}

Fig.prototype.kind = function(){
  result = dll.fig_draw_fig_kind(this)
  return result
}

Fig.prototype.setKind = function(kind){
  dll.fig_draw_fig_set_kind(this, kind)
}

Fig.prototype.zlevel = function(){
  result = dll.fig_draw_fig_z_level(this)
  return result
}

Fig.prototype.setZLevel = function(z_level){
  dll.fig_draw_fig_set_zlevel(this, z_level)
}

Fig.prototype.x = function(){
  result = dll.fig_draw_fig_x(this)
  return result
}

Fig.prototype.y = function(){
  result = dll.fig_draw_fig_y(this)
  return result
}

Fig.prototype.width = function(){
  result = dll.fig_draw_fig_width(this)
  return result
}

Fig.prototype.height = function(){
  result = dll.fig_draw_fig_height(this)
  return result
}

Fig.prototype.setScreenBox = function(x, y, w, h){
  dll.fig_draw_fig_set_screen_box(this, x, y, w, h)
}

Fig.prototype.setFillColor = function(r, g, b, a){
  dll.fig_draw_fig_set_fill_color(this, r, g, b, a)
}

Fig.prototype.setRotation = function(rotation){
  dll.fig_draw_fig_set_rotation(this, rotation)
}

RenderList = Struct({'nimRef': 'uint64'});
RenderList.prototype.isNull = function(){
  return this.nimRef == 0;
};
RenderList.prototype.isEqual = function(other){
  return this.nimRef == other.nimRef;
};
RenderList.prototype.unref = function(){
  return dll.fig_draw_render_list_unref(this)
};
function newRenderList(){
  var result = dll.fig_draw_new_render_list()
  const registry = new FinalizationRegistry(function(obj) {
    console.log("js unref")
    obj.unref()
  });
  registry.register(result, null);
  return result
}

RenderList.prototype.copy = function(){
  result = dll.fig_draw_render_list_copy(this)
  return result
}

RenderList.prototype.clear = function(){
  dll.fig_draw_render_list_clear(this)
}

RenderList.prototype.nodeCount = function(){
  result = dll.fig_draw_render_list_node_count(this)
  return result
}

RenderList.prototype.rootCount = function(){
  result = dll.fig_draw_render_list_root_count(this)
  return result
}

RenderList.prototype.addRoot = function(root){
  result = dll.fig_draw_render_list_add_root(this, root)
  return result
}

RenderList.prototype.addChild = function(parent_idx, child){
  result = dll.fig_draw_render_list_add_child(this, parent_idx, child)
  return result
}

RenderList.prototype.getNode = function(node_idx){
  result = dll.fig_draw_render_list_get_node(this, node_idx)
  return result
}

RenderList.prototype.getRootId = function(root_idx){
  result = dll.fig_draw_render_list_get_root_id(this, root_idx)
  return result
}

Renders = Struct({'nimRef': 'uint64'});
Renders.prototype.isNull = function(){
  return this.nimRef == 0;
};
Renders.prototype.isEqual = function(other){
  return this.nimRef == other.nimRef;
};
Renders.prototype.unref = function(){
  return dll.fig_draw_renders_unref(this)
};
function newRenders(){
  var result = dll.fig_draw_new_renders()
  const registry = new FinalizationRegistry(function(obj) {
    console.log("js unref")
    obj.unref()
  });
  registry.register(result, null);
  return result
}

Renders.prototype.clear = function(){
  dll.fig_draw_renders_clear(this)
}

Renders.prototype.containsLayer = function(z_level){
  result = dll.fig_draw_renders_contains_layer(this, z_level)
  return result
}

Renders.prototype.addRoot = function(z_level, root){
  result = dll.fig_draw_renders_add_root(this, z_level, root)
  return result
}

Renders.prototype.addChild = function(z_level, parent_idx, child){
  result = dll.fig_draw_renders_add_child(this, z_level, parent_idx, child)
  return result
}

Renders.prototype.layerNodeCount = function(z_level){
  result = dll.fig_draw_renders_layer_node_count(this, z_level)
  return result
}

Renders.prototype.layerRootCount = function(z_level){
  result = dll.fig_draw_renders_layer_root_count(this, z_level)
  return result
}

Renders.prototype.getLayerNode = function(z_level, node_idx){
  result = dll.fig_draw_renders_get_layer_node(this, z_level, node_idx)
  return result
}

function newRectangleFig(x, y, w, h){
  result = dll.fig_draw_new_rectangle_fig(x, y, w, h)
  return result
}

function newTextFig(x, y, w, h){
  result = dll.fig_draw_new_text_fig(x, y, w, h)
  return result
}

function newImageFig(x, y, w, h, image_id){
  result = dll.fig_draw_new_image_fig(x, y, w, h, image_id)
  return result
}

function newTransformFig(x, y, w, h, tx, ty){
  result = dll.fig_draw_new_transform_fig(x, y, w, h, tx, ty)
  return result
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

function siwinBackendNameBinding(){
  result = dll.fig_draw_siwin_backend_name_binding()
  return result
}

function siwinWindowTitleBinding(suffix){
  result = dll.fig_draw_siwin_window_title_binding(suffix)
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
  'fig_draw_fig_unref': ['void', [Fig]],
  'fig_draw_new_fig': [Fig, []],
  'fig_draw_fig_copy': [Fig, [Fig]],
  'fig_draw_fig_kind': [FigKind, [Fig]],
  'fig_draw_fig_set_kind': ['void', [Fig, FigKind]],
  'fig_draw_fig_z_level': [ZLevel, [Fig]],
  'fig_draw_fig_set_zlevel': ['void', [Fig, ZLevel]],
  'fig_draw_fig_x': ['float', [Fig]],
  'fig_draw_fig_y': ['float', [Fig]],
  'fig_draw_fig_width': ['float', [Fig]],
  'fig_draw_fig_height': ['float', [Fig]],
  'fig_draw_fig_set_screen_box': ['void', [Fig, 'float', 'float', 'float', 'float']],
  'fig_draw_fig_set_fill_color': ['void', [Fig, 'uint8', 'uint8', 'uint8', 'uint8']],
  'fig_draw_fig_set_rotation': ['void', [Fig, 'float']],
  'fig_draw_render_list_unref': ['void', [RenderList]],
  'fig_draw_new_render_list': [RenderList, []],
  'fig_draw_render_list_copy': [RenderList, [RenderList]],
  'fig_draw_render_list_clear': ['void', [RenderList]],
  'fig_draw_render_list_node_count': ['int64', [RenderList]],
  'fig_draw_render_list_root_count': ['int64', [RenderList]],
  'fig_draw_render_list_add_root': ['int16', [RenderList, Fig]],
  'fig_draw_render_list_add_child': ['int16', [RenderList, 'int16', Fig]],
  'fig_draw_render_list_get_node': [Fig, [RenderList, 'int16']],
  'fig_draw_render_list_get_root_id': ['int16', [RenderList, 'int16']],
  'fig_draw_renders_unref': ['void', [Renders]],
  'fig_draw_new_renders': [Renders, []],
  'fig_draw_renders_clear': ['void', [Renders]],
  'fig_draw_renders_contains_layer': ['bool', [Renders, ZLevel]],
  'fig_draw_renders_add_root': ['int16', [Renders, ZLevel, Fig]],
  'fig_draw_renders_add_child': ['int16', [Renders, ZLevel, 'int16', Fig]],
  'fig_draw_renders_layer_node_count': ['int64', [Renders, ZLevel]],
  'fig_draw_renders_layer_root_count': ['int64', [Renders, ZLevel]],
  'fig_draw_renders_get_layer_node': [Fig, [Renders, ZLevel, 'int16']],
  'fig_draw_new_rectangle_fig': [Fig, ['float', 'float', 'float', 'float']],
  'fig_draw_new_text_fig': [Fig, ['float', 'float', 'float', 'float']],
  'fig_draw_new_image_fig': [Fig, ['float', 'float', 'float', 'float', 'int64']],
  'fig_draw_new_transform_fig': [Fig, ['float', 'float', 'float', 'float', 'float', 'float']],
  'fig_draw_fig_data_dir': ['string', []],
  'fig_draw_set_fig_data_dir': ['void', ['string']],
  'fig_draw_fig_ui_scale': ['float', []],
  'fig_draw_set_fig_ui_scale': ['void', ['float']],
  'fig_draw_scaled': ['float', ['float']],
  'fig_draw_descaled': ['float', ['float']],
  'fig_draw_siwin_backend_name_binding': ['string', []],
  'fig_draw_siwin_window_title_binding': ['string', ['string']],
});

exports.FigKind = FigKind
exports.FIG_KIND = 0
exports.FigType = Fig
exports.Fig = newFig
exports.RenderListType = RenderList
exports.RenderList = newRenderList
exports.RendersType = Renders
exports.Renders = newRenders
exports.newRectangleFig = newRectangleFig
exports.newTextFig = newTextFig
exports.newImageFig = newImageFig
exports.newTransformFig = newTransformFig
exports.figDataDir = figDataDir
exports.setFigDataDir = setFigDataDir
exports.figUiScale = figUiScale
exports.setFigUiScale = setFigUiScale
exports.scaled = scaled
exports.descaled = descaled
exports.siwinBackendNameBinding = siwinBackendNameBinding
exports.siwinWindowTitleBinding = siwinWindowTitleBinding
