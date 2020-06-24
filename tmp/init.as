funcdef void Callback();

class Object {
  Callback @cb = null;

  Object(Callback @cb = null) {
    @this.cb = cb;
  }
};

class List {
  array<Object@> @objects = {
    @Object(null),
    @Object(null),
    @Object()
  };
};

void init() {
  message("init()");

  auto @list = List();

  auto len = list.objects.length();
  for (uint i = 0; i < len; i++) {
    auto @s = list.objects[i];
    if (s is null) {
      message("[" + fmtInt(i) + "] = NULL");
      continue;
    }
    message("[" + fmtInt(i) + "] = not null");
  }
}
