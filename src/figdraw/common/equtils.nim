import std/macros

## ugh -- https://forum.nim-lang.org/t/6781

proc ifNeqRetFalse(fld,w,v:NimNode):NimNode =
  quote do:
    if `w`.`fld` != `v`.`fld`: return false
proc genIfStmts(recList,i,j:NimNode):NimNode =
  result = newStmtList()
  case recList.kind
  of nnkRecList:
    for idDef in recList:
      expectKind(idDef,nnkIdentDefs)
      result.add idDef[0].ifNeqRetFalse(i,j)
  of nnkIdentDefs:
    result.add recList[0].ifNeqRetFalse(i,j)
  else: error "expected RecList or IdentDefs got" & recList.repr

macro equalsImpl*[T:object](a,b:T): untyped =
  template ifNeqRetFalse(fld:typed):untyped = ifNeqRetFalse(fld,a,b)
  template genIfStmts(recList:typed):untyped = genIfStmts(recList,a,b)
  
  let tImpl = a.getTypeImpl
  result = newStmtList()
  result.add quote do:
    result = true
  let records = tImpl[2]
  records.expectKind(nnkRecList)
  for field in records:
    case field.kind
    of nnkIdentDefs:
      result.add field[0].ifNeqRetFalse
    of nnkRecCase:
      let discrim = field[0][0]
      result.add discrim.ifNeqRetFalse
      var casestmt = newNimNode(nnkCaseStmt)
      casestmt.add newDotExpr(a,discrim)
      for ofbranch in field[1..^1]:
        case ofbranch.kind
        of nnkOfBranch:
          let testVal = ofbranch[0]
          let reclst = ofbranch[1]
          casestmt.add nnkOfBranch.newTree(testVal,reclst.genIfStmts)
        of nnkElse:
          let reclst = ofbranch[0]
          casestmt.add nnkElse.newTree(reclst.genIfStmts)
        else: error "Expected OfBranch or Else, got" & ofbranch.repr
      result.add casestmt
    else:
      error "Expected IdentDefs or RecCase, got " & field.repr
  #echo result.repr
