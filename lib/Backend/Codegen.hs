{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DataKinds #-}

module Backend.Codegen where

import Backend.Compiler
import Backend.CompilerUtils
import Backend.Instructions
import Backend.Reg
import Control.Monad.Except
import Control.Monad.State.Strict (gets)
import Data.List
import Grammar
import qualified SymbolTable
import qualified Symbol

parseProgram :: Program -> Compiler ()
parseProgram program = do
  let (Program stmts) = program
  mapM_ execStmt stmts

execStmt :: Stmt -> Compiler ()
execStmt stmt = case stmt of
  StmtDeclare  stmt -> execStmtDeclare stmt
  StmtAssign   stmt -> execStmtAssign stmt
  StmtRead     stmt -> execStmtRead stmt
  StmtWrite    stmt -> execStmtWrite stmt
  StmtIf       stmt -> execStmtIf stmt
  StmtIfElse   stmt -> execStmtIfElse stmt
  StmtWhile    stmt -> execStmtWhile stmt
  StmtDoWhile  stmt -> execStmtDoWhile stmt
  StmtBreak    stmt -> execStmtBreak stmt
  StmtContinue stmt -> execStmtContinue stmt

execStmtDeclare :: StmtDeclare -> Compiler ()
execStmtDeclare _ = return ()

execStmtAssign :: StmtAssign -> Compiler ()
execStmtAssign stmt = do
  let (MkStmtAssign lhs rhs _) = stmt
  rhsReg    <- getRValueInReg rhs
  lhsLocReg <- getLValueLocInReg lhs
  appendCode [XSM_MOV_IndDst lhsLocReg rhsReg]
  releaseReg lhsLocReg
  releaseReg rhsReg
  return ()

execStmtRead :: StmtRead -> Compiler ()
execStmtRead stmt = do
  let MkStmtRead lValue _ = stmt
  lValueLocReg <- getLValueLocInReg lValue
  t1           <- getFreeReg
  let code =
        [ XSM_MOV_Int t1 7 -- arg1: Call Number (Read = 7)
        , XSM_PUSH t1
        , XSM_MOV_Int t1 (-1) -- arg2: File Pointer (Stdin = -1)
        , XSM_PUSH t1
        , XSM_PUSH lValueLocReg -- arg3: Buffer loc
        , XSM_PUSH R0 -- arg4: unused
        , XSM_PUSH R0 -- arg5: unused
        , XSM_INT 6 -- Int 6 = Read System Call
        , XSM_POP t1 -- arg5
        , XSM_POP t1 -- arg4
        , XSM_POP t1 -- arg3
        , XSM_POP t1 -- arg2
        , XSM_POP t1 -- arg1
        ]
  appendCode code
  releaseReg t1
  releaseReg lValueLocReg

execStmtWrite :: StmtWrite -> Compiler ()
execStmtWrite stmt = do
  let MkStmtWrite rValue _ = stmt
  reg <- getRValueInReg rValue
  printReg reg
  releaseReg reg

execStmtIf :: StmtIf -> Compiler ()
execStmtIf stmt = do
  let MkStmtIf condition stmts _ = stmt
  condReg  <- getRValueInReg condition
  endLabel <- getNewLabel
  appendCode [XSM_UTJ $ XSM_UTJ_JZ condReg endLabel]
  mapM_ execStmt stmts
  installLabel endLabel
  releaseReg condReg

execStmtIfElse :: StmtIfElse -> Compiler ()
execStmtIfElse stmt = do
  let MkStmtIfElse condition stmtsThen stmtsElse _ = stmt
  condReg   <- getRValueInReg condition
  elseLabel <- getNewLabel
  endLabel  <- getNewLabel
  appendCode [XSM_UTJ $ XSM_UTJ_JZ condReg elseLabel]
  mapM_ execStmt stmtsThen
  appendCode [XSM_UTJ $ XSM_UTJ_JMP endLabel]
  installLabel elseLabel
  mapM_ execStmt stmtsElse
  installLabel endLabel
  releaseReg condReg

loopBody :: (String -> String -> Compiler ()) -> Compiler ()
loopBody body = do
  startLabel <- getNewLabel
  endLabel   <- getNewLabel
  pushLoopContinueLabel startLabel
  pushLoopBreakLabel endLabel
  installLabel startLabel
  body startLabel endLabel
  installLabel endLabel
  _ <- popLoopContinueLabel
  _ <- popLoopBreakLabel
  return ()

execStmtWhile :: StmtWhile -> Compiler ()
execStmtWhile stmt = do
  let MkStmtWhile condition stmts _ = stmt
  r <- getRValueInReg condition
  loopBody $ \startLabel endLabel -> do
    appendCode [XSM_UTJ $ XSM_UTJ_JZ r endLabel]
    mapM_ execStmt stmts
    appendCode [XSM_UTJ $ XSM_UTJ_JMP startLabel]
  releaseReg r

execStmtDoWhile :: StmtDoWhile -> Compiler ()
execStmtDoWhile stmt = do
  let MkStmtDoWhile condition stmts _ = stmt
  r <- getRValueInReg condition
  loopBody $ \startLabel endLabel -> do
    mapM_ execStmt stmts
    appendCode [XSM_UTJ $ XSM_UTJ_JZ r endLabel]
    appendCode [XSM_UTJ $ XSM_UTJ_JMP startLabel]
  releaseReg r

execStmtBreak :: StmtBreak -> Compiler ()
execStmtBreak _ = do
  endLabel <- peekLoopBreakLabel
  appendCode [XSM_UTJ $ XSM_UTJ_JMP endLabel]

execStmtContinue :: StmtContinue -> Compiler ()
execStmtContinue _ = do
  endLabel <- peekLoopContinueLabel
  appendCode [XSM_UTJ $ XSM_UTJ_JMP endLabel]

printReg :: Reg -> Compiler ()
printReg reg = do
  t1 <- getFreeReg
  let code =
        [ XSM_MOV_Int t1 5 -- arg1: Call Number (Write = 5)
        , XSM_PUSH t1
        , XSM_MOV_Int t1 (-2) -- arg2: File Pointer (Stdout = -2)
        , XSM_PUSH t1
        , XSM_PUSH reg -- arg3: data to be written
        , XSM_PUSH R0 -- arg4: unused
        , XSM_PUSH R0 -- arg5: unused
        , XSM_INT 7 -- Int 7 = Write System Call
        , XSM_POP t1 -- arg5
        , XSM_POP t1 -- arg4
        , XSM_POP t1 -- arg3
        , XSM_POP t1 -- arg2
        , XSM_POP t1 -- arg1
        ]
  appendCode code
  releaseReg t1

getLValueLocInReg :: LValue -> Compiler Reg
getLValueLocInReg lValue = do
  let ident = Grammar.lValueIdent lValue
  dataType <- getIdentDataType ident
  (reg, _) <- getLValueLocInReg' dataType lValue
  return reg
 where
  getLValueLocInReg' :: Symbol.DataType -> LValue -> Compiler (Reg, Int)
  getLValueLocInReg' dataType lValue = case lValue of
    LValueIdent ident -> do
      dataType' <- getIdentDataType ident
      when (dataType /= dataType')
        $ error "Program bug: data type mismatch in getLValueInReg"
      case dataType of
        Symbol.DataTypeArray{} ->
          error
            $  "Program bug: Can not getLValueInReg, dataType is Array"
            ++ (show dataType)
        _ -> return ()
      reg <- getFreeReg
      loc <- getIdentLocInStack ident
      appendCode [XSM_MOV_Int reg loc]
      return (reg, Symbol.getSize dataType)
    LValueArrayIndex index lValue _ -> case dataType of
      Symbol.DataTypeArray dim innerType -> do
        (reg, innerSize) <- getLValueLocInReg' innerType lValue
        indexReg         <- getRValueInReg index
        t                <- getFreeReg
        appendCode [XSM_MOV_Int t innerSize]
        appendCode [XSM_MUL indexReg t]
        appendCode [XSM_ADD reg indexReg]
        releaseReg t
        releaseReg indexReg
        return (reg, innerSize * dim)
      _ -> error "Program Bug: Dereferencing non-Array type"

getRValueInReg :: RValue -> Compiler Reg
getRValueInReg rValue = case rValue of
  (Exp (ExpNum i _)) -> do
    reg <- getFreeReg
    appendCode [XSM_MOV_Int reg i]
    return reg
  (Exp    (ExpArithmetic e1 op e2 _)) -> execALUInstr (arithOpInstr op) e1 e2
  (Exp    (ExpLogical    e1 op e2 _)) -> execALUInstr (logicOpInstr op) e1 e2
  (LValue lValue                    ) -> do
    reg <- getLValueLocInReg lValue
    appendCode [XSM_MOV_IndSrc reg reg]
    return reg

type ALUInstr = (Reg -> Reg -> XSMInstr)

execALUInstr :: ALUInstr -> RValue -> RValue -> Compiler Reg
execALUInstr instr e1 e2 = do
  r1 <- getRValueInReg e1
  r2 <- getRValueInReg e2
  appendCode [instr r1 r2]
  releaseReg r2
  return r1

arithOpInstr :: OpArithmetic -> ALUInstr
arithOpInstr op = case op of
  OpAdd -> XSM_ADD
  OpSub -> XSM_SUB
  OpMul -> XSM_MUL
  OpDiv -> XSM_DIV
  OpMod -> XSM_MOD

logicOpInstr :: OpLogical -> ALUInstr
logicOpInstr op = case op of
  OpLT -> XSM_LT
  OpGT -> XSM_GT
  OpLE -> XSM_LE
  OpGE -> XSM_GE
  OpNE -> XSM_NE
  OpEQ -> XSM_EQ