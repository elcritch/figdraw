when defined(js):
  import chronicles_stub
  export chronicles_stub
else:
  import pkg/chronicles
  export chronicles
