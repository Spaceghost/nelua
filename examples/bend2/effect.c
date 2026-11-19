static Term example_value(Env e, Term *fields, IoWork *work) {
  (void)e;
  (void)fields;
  (void)work;
  return 73;
}

static void __attribute__((constructor)) example_register(void) {
  io_eff(CID(foreign_value), example_value);
}
