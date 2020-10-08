
class Hitbox {
  bool active;
  uint16 x, y;
  uint8 w, h;

  Hitbox() {
    this.active = true;
  }

  void setBox(uint16 x, uint16 y, uint8 w, uint8 h) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }

  void setActive(bool active) {
    this.active = active;
  }

  bool intersects(const Hitbox &in other) const {
    if ((this.x + this.w) <  other.x) {
      return false;
    }
    if ( this.x           > (other.x + other.w)) {
      return false;
    }
    if ((this.y + this.h) <  other.y) {
      return false;
    }
    if ( this.y           > (other.y + other.h)) {
      return false;
    }
    return true;
  }

  uint16 get_mx() const property {
    return x + (w >> 1);
  }

  uint16 get_my() const property {
    return y + (h >> 1);
  }
};
