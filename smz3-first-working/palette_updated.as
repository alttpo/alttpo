
// called when bsnes changes its color palette:
void palette_updated() {
  //message("palette_updated()");
  if (@worldMapWindow != null) {
    worldMapWindow.redrawMap();
  }
}
