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

SiwinWindowRef = Struct({'nimRef': 'uint64'});
SiwinWindowRef.prototype.isNull = function(){
  return this.nimRef == 0;
};
SiwinWindowRef.prototype.isEqual = function(other){
  return this.nimRef == other.nimRef;
};
SiwinWindowRef.prototype.unref = function(){
  return dll.fig_draw_siwin_window_ref_unref(this)
};

SiwinWindowRef.prototype.closeWindowBinding = function(){
  dll.fig_draw_siwin_window_ref_close_window_binding(this)
}

SiwinWindowRef.prototype.stepWindowBinding = function(){
  dll.fig_draw_siwin_window_ref_step_window_binding(this)
}

SiwinWindowRef.prototype.makeCurrentWindowBinding = function(){
  dll.fig_draw_siwin_window_ref_make_current_window_binding(this)
}

SiwinWindowRef.prototype.windowIsOpenBinding = function(){
  result = dll.fig_draw_siwin_window_ref_window_is_open_binding(this)
  return result
}

SiwinWindowRef.prototype.siwinDisplayServerNameBinding = function(){
  result = dll.fig_draw_siwin_window_ref_siwin_display_server_name_binding(this)
  return result
}

SiwinWindowRef.prototype.backingWidthBinding = function(){
  result = dll.fig_draw_siwin_window_ref_backing_width_binding(this)
  return result
}

SiwinWindowRef.prototype.backingHeightBinding = function(){
  result = dll.fig_draw_siwin_window_ref_backing_height_binding(this)
  return result
}

SiwinWindowRef.prototype.logicalWidthBinding = function(){
  result = dll.fig_draw_siwin_window_ref_logical_width_binding(this)
  return result
}

SiwinWindowRef.prototype.logicalHeightBinding = function(){
  result = dll.fig_draw_siwin_window_ref_logical_height_binding(this)
  return result
}

SiwinWindowRef.prototype.contentScaleBinding = function(){
  result = dll.fig_draw_siwin_window_ref_content_scale_binding(this)
  return result
}

SiwinWindowRef.prototype.configureUiScaleBinding = function(env_var){
  result = dll.fig_draw_siwin_window_ref_configure_ui_scale_binding(this, env_var)
  return result
}

SiwinWindowRef.prototype.refreshUiScaleBinding = function(auto_scale){
  dll.fig_draw_siwin_window_ref_refresh_ui_scale_binding(this, auto_scale)
}

SiwinWindowRef.prototype.presentNowBinding = function(){
  dll.fig_draw_siwin_window_ref_present_now_binding(this)
}

SiwinRendererRef = Struct({'nimRef': 'uint64'});
SiwinRendererRef.prototype.isNull = function(){
  return this.nimRef == 0;
};
SiwinRendererRef.prototype.isEqual = function(other){
  return this.nimRef == other.nimRef;
};
SiwinRendererRef.prototype.unref = function(){
  return dll.fig_draw_siwin_renderer_ref_unref(this)
};

SiwinRendererRef.prototype.siwinBackendNameForRendererBinding = function(){
  result = dll.fig_draw_siwin_renderer_ref_siwin_backend_name_for_renderer_binding(this)
  return result
}

SiwinRendererRef.prototype.siwinWindowTitleForRendererBinding = function(window, suffix){
  result = dll.fig_draw_siwin_renderer_ref_siwin_window_title_for_renderer_binding(this, window, suffix)
  return result
}

SiwinRendererRef.prototype.setupBackendBinding = function(window){
  dll.fig_draw_siwin_renderer_ref_setup_backend_binding(this, window)
}

SiwinRendererRef.prototype.beginFrameBinding = function(){
  dll.fig_draw_siwin_renderer_ref_begin_frame_binding(this)
}

SiwinRendererRef.prototype.endFrameBinding = function(){
  dll.fig_draw_siwin_renderer_ref_end_frame_binding(this)
}

SiwinMetalLayerRef = Struct({'nimRef': 'uint64'});
SiwinMetalLayerRef.prototype.isNull = function(){
  return this.nimRef == 0;
};
SiwinMetalLayerRef.prototype.isEqual = function(other){
  return this.nimRef == other.nimRef;
};
SiwinMetalLayerRef.prototype.unref = function(){
  return dll.fig_draw_siwin_metal_layer_ref_unref(this)
};

SiwinMetalLayerRef.prototype.updateMetalLayerBinding = function(window){
  dll.fig_draw_siwin_metal_layer_ref_update_metal_layer_binding(this, window)
}

SiwinMetalLayerRef.prototype.setOpaqueBinding = function(opaque){
  dll.fig_draw_siwin_metal_layer_ref_set_opaque_binding(this, opaque)
}

function siwinBackendNameBinding(){
  result = dll.fig_draw_siwin_backend_name_binding()
  return result
}

function siwinWindowTitleBinding(suffix){
  result = dll.fig_draw_siwin_window_title_binding(suffix)
  return result
}

function sharedSiwinGlobalsPtrBinding(){
  result = dll.fig_draw_shared_siwin_globals_ptr_binding()
  return result
}

function newSiwinRendererBinding(atlas_size, pixel_scale){
  result = dll.fig_draw_new_siwin_renderer_binding(atlas_size, pixel_scale)
  return result
}

function newSiwinWindowBinding(width, height, fullscreen, title, vsync, msaa, resizable, frameless, transparent){
  result = dll.fig_draw_new_siwin_window_binding(width, height, fullscreen, title, vsync, msaa, resizable, frameless, transparent)
  return result
}

function newSiwinWindowForRendererBinding(renderer, width, height, fullscreen, title, vsync, msaa, resizable, frameless, transparent){
  result = dll.fig_draw_new_siwin_window_for_renderer_binding(renderer, width, height, fullscreen, title, vsync, msaa, resizable, frameless, transparent)
  return result
}

function attachMetalLayerBinding(window, device_ptr){
  result = dll.fig_draw_attach_metal_layer_binding(window, device_ptr)
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
  'fig_draw_siwin_window_ref_unref': ['void', [SiwinWindowRef]],
  'fig_draw_siwin_window_ref_close_window_binding': ['void', [SiwinWindowRef]],
  'fig_draw_siwin_window_ref_step_window_binding': ['void', [SiwinWindowRef]],
  'fig_draw_siwin_window_ref_make_current_window_binding': ['void', [SiwinWindowRef]],
  'fig_draw_siwin_window_ref_window_is_open_binding': ['bool', [SiwinWindowRef]],
  'fig_draw_siwin_window_ref_siwin_display_server_name_binding': ['string', [SiwinWindowRef]],
  'fig_draw_siwin_window_ref_backing_width_binding': ['int32', [SiwinWindowRef]],
  'fig_draw_siwin_window_ref_backing_height_binding': ['int32', [SiwinWindowRef]],
  'fig_draw_siwin_window_ref_logical_width_binding': ['float', [SiwinWindowRef]],
  'fig_draw_siwin_window_ref_logical_height_binding': ['float', [SiwinWindowRef]],
  'fig_draw_siwin_window_ref_content_scale_binding': ['float', [SiwinWindowRef]],
  'fig_draw_siwin_window_ref_configure_ui_scale_binding': ['bool', [SiwinWindowRef, 'string']],
  'fig_draw_siwin_window_ref_refresh_ui_scale_binding': ['void', [SiwinWindowRef, 'bool']],
  'fig_draw_siwin_window_ref_present_now_binding': ['void', [SiwinWindowRef]],
  'fig_draw_siwin_renderer_ref_unref': ['void', [SiwinRendererRef]],
  'fig_draw_siwin_renderer_ref_siwin_backend_name_for_renderer_binding': ['string', [SiwinRendererRef]],
  'fig_draw_siwin_renderer_ref_siwin_window_title_for_renderer_binding': ['string', [SiwinRendererRef, SiwinWindowRef, 'string']],
  'fig_draw_siwin_renderer_ref_setup_backend_binding': ['void', [SiwinRendererRef, SiwinWindowRef]],
  'fig_draw_siwin_renderer_ref_begin_frame_binding': ['void', [SiwinRendererRef]],
  'fig_draw_siwin_renderer_ref_end_frame_binding': ['void', [SiwinRendererRef]],
  'fig_draw_siwin_metal_layer_ref_unref': ['void', [SiwinMetalLayerRef]],
  'fig_draw_siwin_metal_layer_ref_update_metal_layer_binding': ['void', [SiwinMetalLayerRef, SiwinWindowRef]],
  'fig_draw_siwin_metal_layer_ref_set_opaque_binding': ['void', [SiwinMetalLayerRef, 'bool']],
  'fig_draw_siwin_backend_name_binding': ['string', []],
  'fig_draw_siwin_window_title_binding': ['string', ['string']],
  'fig_draw_shared_siwin_globals_ptr_binding': ['uint64', []],
  'fig_draw_new_siwin_renderer_binding': [SiwinRendererRef, ['int64', 'float']],
  'fig_draw_new_siwin_window_binding': [SiwinWindowRef, ['int32', 'int32', 'bool', 'string', 'bool', 'int32', 'bool', 'bool', 'bool']],
  'fig_draw_new_siwin_window_for_renderer_binding': [SiwinWindowRef, [SiwinRendererRef, 'int32', 'int32', 'bool', 'string', 'bool', 'int32', 'bool', 'bool', 'bool']],
  'fig_draw_attach_metal_layer_binding': [SiwinMetalLayerRef, [SiwinWindowRef, 'uint64']],
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
exports.SiwinWindowRefType = SiwinWindowRef
exports.SiwinRendererRefType = SiwinRendererRef
exports.SiwinMetalLayerRefType = SiwinMetalLayerRef
exports.siwinBackendNameBinding = siwinBackendNameBinding
exports.siwinWindowTitleBinding = siwinWindowTitleBinding
exports.sharedSiwinGlobalsPtrBinding = sharedSiwinGlobalsPtrBinding
exports.newSiwinRendererBinding = newSiwinRendererBinding
exports.newSiwinWindowBinding = newSiwinWindowBinding
exports.newSiwinWindowForRendererBinding = newSiwinWindowForRendererBinding
exports.attachMetalLayerBinding = attachMetalLayerBinding
