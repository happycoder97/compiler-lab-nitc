{-# LANGUAGE LambdaCase #-}
module Test.Grammar where

import Grammar
import Span
import Test.GrammarUtils
import Test.Utils
import Test.Tasty (TestTree)
import Test.Tasty.HUnit

test_varDeclare :: TestTree
test_varDeclare =
  testCaseSteps "Variable Declaration" $ \step -> do
    step "Declare var"
    _ <- assertRight $ runGrammarM initGrammarState $ do
      doVarDeclare "foo" TypeInt [5, 10] (Span 0 0)
      mkLValue (spanW "foo")
               (spanW . RExp . ExpNum <$> [1, 2])

    step "Redeclare var"
    assertError $ runGrammarM initGrammarState $ do
      doVarDeclare "foo" TypeInt  [1, 2] (Span 0 0)
      doVarDeclare "foo" TypeInt  [2, 2] (Span 0 0)


test_mkLValue :: TestTree
test_mkLValue = testCaseSteps "mkLValue" $ \step -> do
  step "Undeclared LValue"
  assertError $ runGrammarM initGrammarState $ mkLValue
    (spanW "foo")
    []

  step "Declared LValue"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeInt [] (Span 0 0)
    mkLValue (spanW "foo") []

  step "Too many index"
  assertError $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeInt [1, 2, 3] (Span 0 0)
    mkLValue (spanW "foo")
             (spanW . RExp . ExpNum <$> [0, 1, 0, 0])

  step "Correct index"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeInt [5, 5] (Span 0 0)
    mkLValue (spanW "foo")
             (spanW . RExp . ExpNum <$> [2, 2])
  return ()

test_stmtAssign :: TestTree
test_stmtAssign = testCaseSteps "StmtAssign" $ \step -> do
  step "Assign constant"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeInt [5, 10] (Span 0 0)
    mkStmtAssign (LValue (RExp . ExpNum <$> [1, 2]) "foo")
                 (RExp $ ExpNum 10)
                 (Span 0 0)

  step "Assign variable"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeInt [5, 10] (Span 0 0)
    doVarDeclare "bar" TypeInt [] (Span 0 0)
    mkStmtAssign (LValue (RExp . ExpNum <$> [1, 2]) "foo")
                 (RLValue $ LValue [] "bar")
                 (Span 0 0)

  step "Assign self"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeInt [] (Span 0 0)
    mkStmtAssign (LValue [] "foo")
                 (RLValue $ LValue [] "foo")
                 (Span 0 0)

  step "Type mismatch"
  assertError $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeString [5, 10] (Span 0 0)
    mkStmtAssign (LValue (RExp . ExpNum <$> [1, 2]) "foo")
                 (RExp $ ExpNum 10)
                 (Span 0 0)

  step "Assign to array"
  assertError $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeInt [5, 10] (Span 0 0)
    doVarDeclare "bar" TypeInt [5, 10] (Span 0 0)
    mkStmtAssign (LValue [] "foo")
                 (RLValue $ LValue [] "bar")
                 (Span 0 0)

test_stmtRead :: TestTree
test_stmtRead = testCaseSteps "StmtRead" $ \step -> do
  step "Read Int"
  _ <- assertRight $ runGrammarM initGrammarState $ do
   doVarDeclare "foo" TypeInt [5, 10] (Span 0 0)
   mkStmtRead $ SpanW
      (LValue (RExp . ExpNum <$> [0, 1]) "foo")
      (Span 0 0)

  step "Read String"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeString [5, 10] (Span 0 0)
    mkStmtRead $ SpanW
      (LValue (RExp . ExpNum <$> [0, 1]) "foo")
      (Span 0 0)

  step "Read bool"
  assertError $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeBool [5, 10] (Span 0 0)
    mkStmtRead $ SpanW (LValue [] "foo") (Span 0 0)

  step "Read array"
  assertError $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeInt [1] (Span 0 0)
    mkStmtRead $ SpanW (LValue [] "foo") (Span 0 0)


test_stmtWrite :: TestTree
test_stmtWrite = testCaseSteps "StmtWrite" $ \step -> do
  step "Write Int"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeInt [] (Span 0 0)
    mkStmtWrite
      $ SpanW (RLValue $ LValue [] "foo") (Span 0 0)

  step "Write String"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeString [] (Span 0 0)
    mkStmtWrite
      $ SpanW (RLValue $ LValue [] "foo") (Span 0 0)

  step "Write Bool"
  assertError $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeBool [] (Span 0 0)
    mkStmtWrite
      $ SpanW (RLValue $ LValue [] "foo") (Span 0 0)

  step "Write Array"
  assertError $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeInt [1] (Span 0 0)
    mkStmtWrite
      $ SpanW (RLValue $ LValue [] "foo") (Span 0 0)

test_stmtIf :: TestTree
test_stmtIf = testCaseSteps "StmtIf" $ \step -> do
  step "If Bool"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeBool [] (Span 0 0)
    mkStmtIf
      (SpanW (RLValue $ LValue [] "foo") (Span 0 0))
      []

  step "If non Bool"
  assertError $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeInt [] (Span 0 0)
    mkStmtIf
      (SpanW (RLValue $ LValue [] "foo") (Span 0 0))
      []

test_stmtIfElse :: TestTree
test_stmtIfElse = testCaseSteps "StmtIfElse" $ \step -> do
  step "IfElse Bool"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeBool [] (Span 0 0)
    mkStmtIfElse
      (SpanW (RLValue $ LValue [] "foo") (Span 0 0))
      []
      []

  step "IfElse non Bool"
  assertError $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeInt [] (Span 0 0)
    mkStmtIfElse
      (SpanW (RLValue $ LValue [] "foo") (Span 0 0))
      []
      []

test_stmtWhile :: TestTree
test_stmtWhile = testCaseSteps "StmtWhile" $ \step -> do
  step "While Bool"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeBool [] (Span 0 0)
    mkStmtWhile
      (SpanW (RLValue $ LValue [] "foo") (Span 0 0))
      []

  step "While non Bool"
  assertError $ runGrammarM initGrammarState $ do
    doVarDeclare "foo" TypeString [] (Span 0 0)
    mkStmtWhile
      (SpanW (RLValue $ LValue [] "foo") (Span 0 0))
      []

test_stmtBreak :: TestTree
test_stmtBreak = testCaseSteps "StmtBreak" $ \step -> do
  step "Break Inside Loop"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    pushLoop
    mkStmtBreak (Span 0 0)

  step "Break Outside Loop"
  assertError $ runGrammarM initGrammarState $ mkStmtBreak (Span 0 0)

test_stmtContinue :: TestTree
test_stmtContinue =
  testCaseSteps "StmtContinue" $ \step -> do
    step "Continue Inside Loop"
    _ <- assertRight $ runGrammarM initGrammarState $ do
      pushLoop
      mkStmtContinue (Span 0 0)

    step "Continue Outside Loop"
    assertError $ runGrammarM initGrammarState $ mkStmtContinue
      (Span 0 0)

test_funcDeclare :: TestTree
test_funcDeclare = testCaseSteps "Func Declare" $ \step ->
  do
    step "Declare function"
    _ <- assertRight $ runGrammarM initGrammarState $ do
      doFuncDeclare
        TypeInt
        "foo"
        (   flip SpanW (Span 0 0)
        <$> [TypeInt, TypeInt, TypeInt]
        )
        (Span 0 0)

    -- TODO: Check function is actually declared using RValue

    step "Redeclare function"
    assertError $ runGrammarM initGrammarState $ do
      doFuncDeclare TypeString "foo" [] (Span 0 0)
      doFuncDeclare TypeString "foo" [] (Span 0 0)

test_funcDefine :: TestTree
test_funcDefine = testCaseSteps "Func Define" $ \step -> do

  step "Declare and define function"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    doFuncDeclare TypeInt
                  "foo"
                  (spanW <$> [TypeInt, TypeInt])
                  (Span 0 0)
    define <- doFuncDefine
      TypeInt
      "foo"
      (spanW <$> [("fff", TypeInt), ("bar", TypeInt)])
      (Span 0 0)
    define []

  step "Define without declare"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    define <- doFuncDefine
      TypeInt
      "foo"
      (   flip SpanW (Span 0 0)
      <$> [("fff", TypeInt), ("bar", TypeInt)]
      )
      (Span 0 0)
    define []

  step "Redeclare function"
  assertError $ runGrammarM initGrammarState $ do
    define <- doFuncDefine
      TypeInt
      "foo"
      (   flip SpanW (Span 0 0)
      <$> [("fff", TypeInt), ("bar", TypeInt)]
      )
      (Span 0 0)
    define []
    doFuncDeclare TypeString "foo" [] (Span 0 0)

  step "Function declaration mismatch - return type"
  assertError $ runGrammarM initGrammarState $ do
    doFuncDeclare TypeString "foo" [] (Span 0 0)
    _ <- doFuncDefine TypeInt "foo" [] (Span 0 0)
    return ()

  step "Function declaration mismatch - args"
  assertError $ runGrammarM initGrammarState $ do
    doFuncDeclare TypeString "foo" [] (Span 0 0)
    _ <- doFuncDefine TypeString
                      "foo"
                      [SpanW ("ff", TypeInt) (Span 0 0)]
                      (Span 0 0)
    return ()

test_mkExpArithmetic :: TestTree
test_mkExpArithmetic =
  testCaseSteps "Exp Arithmetic" $ \step -> do
    step "Int Int"
    _ <- assertRight $ runGrammarM initGrammarState $ mkExpArithmetic
      (spanW (RExp $ ExpNum 1))
      OpAdd
      (spanW (RExp $ ExpNum 1))

    step "Str Int"
    assertError $ runGrammarM initGrammarState $ mkExpArithmetic
      (spanW (RExp $ ExpStr "Foo"))
      OpAdd
      (spanW (RExp $ ExpNum 1))

    step "Int Str"
    assertError $ runGrammarM initGrammarState $ mkExpArithmetic
      (spanW (RExp $ ExpNum 1))
      OpAdd
      (spanW (RExp $ ExpStr "Foo"))

    return ()

test_mkExpLogical :: TestTree
test_mkExpLogical = testCaseSteps "Exp Logical" $ \step ->
  do
    step "Int Int"
    _ <- assertRight $ runGrammarM initGrammarState $ mkExpLogical
      (spanW (RExp $ ExpNum 1))
      OpLT
      (spanW (RExp $ ExpNum 1))

    step "Str Str"
    _ <- assertRight $ runGrammarM initGrammarState $ mkExpLogical
      (spanW (RExp $ ExpStr "A"))
      OpLT
      (spanW (RExp $ ExpStr "B"))

    step "Int Str"
    assertError $ runGrammarM initGrammarState $ mkExpLogical
      (spanW (RExp $ ExpNum 1))
      OpLT
      (spanW (RExp $ ExpStr "B"))

    return ()

test_mkExpFuncCall :: TestTree
test_mkExpFuncCall = testCaseSteps "mkExpFuncCall" $ \step -> do
  step "Undeclared function"
  assertError $ runGrammarM initGrammarState $ do
    mkExpFuncCall "foo" [] (Span 0 0)

  step "Declared function"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    doFuncDeclare TypeInt "foo" [] (Span 0 0)
    mkExpFuncCall "foo" [] (Span 0 0)

  step "arg type mismatch"
  assertError $ runGrammarM initGrammarState $ do
    doFuncDeclare TypeInt "foo" ( spanW <$> [TypeInt] ) (Span 0 0)
    mkExpFuncCall "foo" ( spanW . RExp . ExpNum <$> [1, 2] ) (Span 0 0)

  step "assign to var"
  _ <- assertRight $ runGrammarM initGrammarState $ do
    doVarDeclare "bar" TypeInt [] (Span 0 0)
    doFuncDeclare TypeInt "foo" [] (Span 0 0)
    exp <- mkExpFuncCall "foo" [] (Span 0 0)
    lValue <- mkLValue (spanW "bar") []
    mkStmtAssign lValue exp (Span 0 0)

  return ()
