---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2014
---------------------------------------------------------------------------

{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE QuasiQuotes               #-}
{-# LANGUAGE DeriveDataTypeable        #-}

{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE UndecidableInstances       #-}
{-# LANGUAGE OverloadedStrings          #-}


--{-# LANGUAGE OverlappingInstances #-}

module Luna.Parser.Parser where


import           Control.Applicative
import           Control.Exception            (bracket)
import           Flowbox.Control.Monad.State  hiding (mapM_, (<$!>), join, mapM, State)
import qualified Data.ByteString              as B
import qualified Data.ByteString.UTF8         as UTF8
import           Data.CharSet.ByteSet         as S
import           Data.Default
import           Flowbox.Prelude              hiding (noneOf, maybe, element, cons)
import qualified Flowbox.Prelude              as Prelude
import qualified Luna.Data.ASTInfo            as ASTInfo
import qualified Luna.Parser.Token            as Tok
import qualified Luna.Parser.State            as ParserState
import           Luna.Parser.State            (ParserState)
import           System.Environment           (getArgs)
import           System.IO                    (IOMode (ReadMode), hClose, openFile)
import           System.IO                    (stdout)
import           Text.Parser.Token.Highlight
import           Text.Parser.Token.Style
import           Text.PrettyPrint.ANSI.Leijen (displayIO, linebreak, renderPretty)
import qualified Text.PrettyPrint.ANSI.Leijen as Leijen
import           Text.RawString.QQ
import           Text.Trifecta                hiding (parseFromFile, parseByteString, parseString)
import qualified Text.Trifecta                as Trifecta
import           Text.Trifecta.Delta          as Delta
import qualified Luna.Data.Config             as Config
import qualified Luna.Pragma.Pragma           as Pragma
import           Luna.Pragma.Pragma           (IsPragma)
import           Data.Typeable
import           Data.String.Utils            (join)
import           Luna.Parser.Combinators
import           Text.Parser.Expression
import           Text.Parser.LookAhead
import           Data.Char                    (isSpace)
import qualified Data.ByteString as ByteStr
import           Luna.Syntax.Name.Path        (NamePath(NamePath))
import qualified Luna.Syntax.Name.Path        as NamePath
import qualified Luna.Syntax.Name.Pattern     as NamePat
import           Luna.Syntax.Name.Pattern     (NamePat(NamePat), Segment(Segment))
import qualified Luna.Syntax.Name             as Name
import           Luna.Syntax.Name             (VName, vname, TName, tname, TVName, tvname)

--import qualified Luna.Data.Namespace          as Namespace
import qualified Luna.Data.Namespace.State    as Namespace
import qualified Luna.Data.StructInfo          as StructInfo
import           Luna.Data.StructInfo         (OriginInfo(OriginInfo))
import qualified Luna.Syntax.AST              as AST
import qualified Luna.Syntax.Traversals       as AST
import qualified Data.Maps                    as Map
import           Data.Maybe                   (isJust, fromJust)
import qualified Flowbox.Data.MapForest       as MapForest
import qualified Data.List                    as List
import qualified Luna.Parser.Pragma           as Pragma

import           Text.EditDistance            --(defaultEditCosts, levenshteinDistance, EditCosts, Costs(..))
import           Text.PhoneticCode.Phonix     (phonix)
import           Data.Function                (on)
import           Data.List                    (sort, sortBy)
import           Luna.Syntax.Name.Path (QualPath(QualPath))

import qualified Data.IntMap  as IntMap

--import Data.HashSet (HashSet)
import qualified Data.HashSet as HashSet

import qualified Luna.Parser.Indent as Indent


import qualified Luna.Syntax.Expr as Expr
import           Luna.Syntax.Expr (LExpr, Expr(Expr))


import qualified Luna.Syntax.Decl   as Decl
import           Luna.Syntax.Decl   (LDecl, Field(Field))
import qualified Luna.Syntax.Module as Module
import           Luna.Syntax.Module (Module(Module), LModule)
import           Luna.Syntax.Unit   (Unit(Unit))
import qualified Luna.Syntax.Label  as Label
import           Luna.Syntax.Label  (Label(Label))
import qualified Luna.Syntax.Type   as Type
import           Luna.Syntax.Type   (Type)
import qualified Luna.Syntax.Pat    as Pat
import           Luna.Syntax.Pat    (LPat, Pat)
import qualified Luna.Syntax.Lit    as Lit
import           Luna.Syntax.Arg    (Arg(Arg))
import qualified Luna.Syntax.Native as Native

import qualified Luna.Syntax.Enum       as Enum
import           Luna.Syntax.Enum       (Enumerated, IDTag(IDTag))
import qualified Luna.Syntax.Unit       as Unit


import qualified Data.TypeLevel.Set as TLSet
import           Data.Tuple.Select

import qualified Data.Text.Lazy.Encoding as Text

import           Luna.Syntax.Foreign (Foreign(Foreign))
import qualified Luna.Syntax.Foreign as Foreign

import Luna.Parser.Type

import Luna.Parser.Builder (labeled, label, nextID, qualifiedPath, withLabeled)


mtry p = try p <|> pure mempty

vName = Name.V <$> varOp
tName = Name.T <$> Tok.typeIdent

anyName = vName <|> tName











--extensionPath   = (,) <$> (((qualifiedPath Tok.typeIdent <?> "extension path") <* Tok.accessor) <|> pure [])
--                      <*> (namePattern <?> "function name")

--namePattern =   (NamePat.single <$> varOp)
--            <|> Tok.parens (NamePat.close <$> (NamePat.multi <$> Tok.varIdent <*> many1 namePatSeg))

--namePatSeg =   (NamePat.Token <$> Tok.varIdent)
--           <|> (NamePat.Hole  <$  Tok.nameWildcard)


--namePattern =   (NamePath.single <$> varOp)
--            <|> Tok.parens (NamePath.multi <$> Tok.varIdent <*> many1 Tok.varIdent)


argList       p = try (sepBy2 p Tok.separator) <|> many p <?> "argument list"
argList'      p = braces (sepBy2 p Tok.separator) <|> ((:[]) <$> p) <?> "argument list"
list          p = Tok.brackets (sepBy p Tok.separator)
anyIdent        = choice [ Tok.varIdent, Tok.typeIdent ]

varOp           = Tok.varIdent <|> Tok.operator







binary   name fun assoc = Infix   (Tok.reservedOp name *> return fun) assoc
binaryM  name fun assoc = Infix   (Tok.reservedOp name *>        fun) assoc
prefix   name fun       = Prefix  (Tok.reservedOp name *> return fun)
prefixM  name fun       = Prefix  (Tok.reservedOp name *>        fun)
prefixfM      fun       = Prefix  (fun)
postfix  name fun       = Postfix (Tok.reservedOp name *> return fun)
postfixM name fun       = Postfix (Tok.reservedOp name *>        fun)


element m = do
    id <- nextID
    ParserState.registerID id
    ast <- m id
    --ParserState.registerAST id ast
    return ast



container m = element $ \id -> ParserState.withNewScope id $ m id




--regVarName m id = do
--    ast <- m id
--    ParserState.regVarName id (AST.name ast)
--    return ast


--nameTok p = element $ regVarName $ \id -> p <*> pure id

tok p = element $ \id -> p <*> pure id

-- Parser translation unit.
-- Provides a global namespace when parsing module, expression etc.
unit p = do
    --FIXME[WD] : change id to datatype
    let id = -666 
    --id <- nextID
    --Unit id <$> ParserState.withNewScope id p
    ParserState.withNewScope id p


-----------------------------------------------------------
-- Definitions
-----------------------------------------------------------


pUnit p = Unit <$> labeled p


decl = choice [ imp, func, cls, typeAlias, typeWrapper ]

----- Modules -----

pModule name path = do
    let qpath = (QualPath path name)
    ParserState.setModPath qpath
    Module qpath <$> Indent.withPos (moduleBlock $ labeled moduleBody)
    where moduleBody = decl <?> "module body"

----- Imports -----

imp = Decl.Imp <$  Tok.kwImport
               <*> (qualifiedPath Tok.typeIdent <?> "import path")
               <*> ((Just <$ Tok.kwAs <*> Tok.typeIdent) <|> pure Nothing)
               <*> (blockBegin importTarget <|> pure [])
               <?> "import declaration"

importTarget =   body Decl.ImpVar varOp 
             <|> body Decl.ImpType Tok.typeIdent
             where body c p = c <$> p <*> ((Just <$ Tok.kwAs <*> p) <|> pure Nothing)


----- type aliases ------

typeAlias = Decl.TpAls <$  Tok.kwAlias 
                       <*> (typeT <?> "new type") 
                       <*  Tok.assignment 
                       <*> (typeT <?> "base type")
                       <?> "type alias"


----- type wrappers ------

typeWrapper = Decl.TpWrp <$  Tok.kwType 
                         <*> (typeT <?> "new type") 
                         <*  Tok.assignment 
                         <*> (typeT <?> "base type")
                         <?> "type wrapper"



----- functions -----

sigVarOp = Tok.explicitName Tok.varIdent <|> Tok.operator

funcSig = try multiSig <|> singleSig

singleSig = NamePat Nothing <$> singleSigSegment <*> pure []
multiSig  = NamePat <$> maybe arg <*> multiSigSegment <*> many multiSigSegment

singleSigSegment = Segment <$> Tok.varIdent <*> many arg
multiSigSegment  = Segment <$> sigVarOp <*> many arg

arg = Arg <$> argPattern
          <*> ((Just <$ Tok.assignment <*> stage1DefArg) <|> pure Nothing)

foreign p = Foreign <$ Tok.kwForeign <*> foreignTarget <*> p 

foreignTarget =   Foreign.Haskell <$ Tok.kwFHaskell
              <|> Foreign.CPP     <$ Tok.kwFCPP

func =   Decl.Foreign <$> foreign (Decl.FFunc <$> funcDecl (char ':' *> (fromString . concat <$> stage1Body2)))
     <|> Decl.Func    <$> funcDecl (char ':' *> stage1Body2)

funcDecl body = Decl.FuncDecl <$  Tok.kwDef
                         <*> extPath
                         <*> funcSig
                         <*> outType
                         <*> body
    where extPath = ((qualifiedPath Tok.typeIdent <?> "extension path") <* Tok.accessor) <|> pure []
          outType = (Just <$> try (Tok.arrow *> typeT)) <|> pure Nothing


----- classes -----

cls = Decl.Data <$> dataDecl

withBlock p = blockStart *> p <* blockEnd

rapp1 a f = f a
rapp2 a b f = f a b

dataDecl = do
    name <- Tok.kwClass *> (Tok.typeIdent <?> "class name")
    Decl.DataDecl <$> pure name 
                  <*> params
                  <**> ( try (withBlock ((rapp2) <$> constructors name <*> bodyBlock))
                         <|> ((rapp2) <$> defConsList name <*> pure [])
                       )
            <?> "class definition"
      where params         = many (tvname <$> Tok.typeVarIdent <?> "class parameter")
            defCons      n = Decl.Cons n <$> (concat <$> many fields)
            defConsList  n = ((:[]) <$> labeled (defCons $ convert n))
            constructors n =   blockBody' (labeled cons) <|> defConsList n
            bodyBlock      = blockBodyOpt $ labeled clsBody 
            clsBody        = choice [ func, cls, typeAlias, typeWrapper ] <?> "class body"


cons         = Decl.Cons <$> Tok.conIdent 
                         <*> ((concat <$> blockBeginFields fields) <|> pure [])
                         <?> "data constructor definition"


fields = do
         (names, cls) <- try ((,) <$> fieldList      <*> typed)
                         <|> ((,) <$> pure [Nothing] <*> termT)
         
         sequence $ fmap (labeled.pure) 
                  $ zipWith3 Field (repeat cls) names (repeat Nothing)

         where fieldList = sepBy1 (Just <$> Tok.varIdent) Tok.separator




typed = Tok.typeDecl *> termT



stage1DefArg = Tok.tokenBlock (many alphaNum)

stage1BodyInner = (many1 $ noneOf "\n\r")
stage1Body = (:) <$> stage1BodyInner <*> (try (spaces *> Indent.checkIndented *> stage1Body) <|> pure [[]])

stage1Body2 = ((:) <$> (try ((<>) <$> Tok.spaces <* Indent.checkIndented <*> stage1BodyInner)) <*> stage1Body2) <|> pure [[]]

--stage1Block = (++) <$> Tok.spaces <* Ident.checkIndented <*> Indent.withPos (indBlockBody p)
--stage1Body2 = (:) <$> (try (Tok.spaces <* Indent.checkIndented <* stage1BodyInner) <|> pure []) <*> stage1Body2
--dokonczyc bo nie ma wciec



-----------------------------------------------------------
-- Patterns
-----------------------------------------------------------
pattern    = choice [ try implTupleP
                    , patCon
                    ]

patTup     = pattern <|> (labeled (Pat.Tuple <$> pure []))

patCon     = choice [ try appP
                    , termP
                    ]

argPattern = termBase termT

termP      = termBase typeT

termBase t = choice [ try (labeled (Pat.Grouped <$> Tok.parens patTup))
                    , try (labeled (Pat.Typed   <$> entP <* Tok.typeDecl <*> t))
                    , entP
                    ]
              <?> "pattern term"

varP       = withLabeled $ \id -> do
                name <- Tok.varIdent
                let np = NamePath.single name
                path <- ParserState.getModPath
                Namespace.regVarName (OriginInfo path id) np
                return $ Pat.Var (fromText name)



--labeled (Pat.Var         <$> Tok.varIdent)

litP       = labeled (Pat.Lit         <$> literal)
implTupleP = labeled (Pat.Tuple       <$> sepBy2 patCon Tok.separator)
wildP      = labeled (Pat.Wildcard    <$  Tok.wildcard)
recWildP   = labeled (Pat.RecWildcard <$  Tok.recWildcard)
conP       = labeled (Pat.Con         <$> Tok.conIdent)
appP       = labeled (Pat.App         <$> conP <*> many1 termP)

entP = choice [ varP
              , litP
              , wildP
              , recWildP
              , conP
              ]


----------------------------------------------------------------------
-- Literals
----------------------------------------------------------------------

literal = choice [ numL, charL, stringL ]
charL   = labeled (Lit.Char   <$> Tok.charLiteral)
stringL = labeled (Lit.String <$> Tok.stringLiteral)
numL    = labeled (Lit.Number <$> Tok.numberL)

-- FIXME [wd]: last parsed char is poorly written with '_' workaround when no char is available
prevParsedChar = do
    Caret delta bs <- careting
    let idx = max 0 . fromIntegral $ column delta - 1
        txt = UTF8.toString bs
    return $ if idx > length txt then '_' else txt !! idx

lastLexemeEmpty = do
    prevChar <- prevParsedChar
    when (isSpace prevChar) $ fail "not empty"


-----------------------------------------------------------
-- Expressions
-----------------------------------------------------------
expr       = tlExpr entBaseE

--FIXME[wd]: exprSimple is broken - it includes func calls. Using pEntBaseSimpleE for now
--exprSimple = tlExpr pEntBaseSimpleE


-- === Top Level pattern, variable, record updates chains === --

tlRecUpd     = assignSeg $ (\vop accs expr -> Expr.RecUpd vop [Expr.FieldUpd accs expr]) <$> varOp <*> many1 recAcc
tlExprPat    = assignSeg $ Expr.Assignment <$> pattern
tlExprPatVar = assignSeg $ Expr.Assignment <$> varP

assignSeg p = p <* Tok.assignment

tlExprExtHead =   try tlExprPat
              <|> tlExprBasicHead

tlExprBasicHead =  try tlExprPatVar
               <|> try tlRecUpd

tlExprParser head base =   (labeled $ head <*> tlExprBasic base)
                       <|> opTupleTE base

tlExpr      = tlExprParser tlExprExtHead
tlExprBasic = tlExprParser tlExprBasicHead

-- === / === --


opE       = opTE entBaseE
opTupleTE base = tupleE $ opTE base

opTE base = buildExpressionParser optableE (appE base)

tupleE p = p <??> ((\id xs x -> label id $ Expr.Tuple (x:xs)) <$> nextID <* Tok.separator <*> sepBy1 p Tok.separator)

--appE base = p <??> (appID (\i a s -> Expr.App i s a) <*> many1 (argE p)) where 
appE base = p <??> ((\i a s -> label i $ callBuilder2 s a) <$> nextID <*> many1 (appArg p)) where 
    p = termE base



termE base = base <??> (flip applyAll <$> many1 (termBaseE base))  ------  many1 (try $ recUpdE))


termBaseE p = choice [ accE
                     , callTermE p
                     ]

recAcc  = (Tok.accessor *> varOp)

accBaseE  = (Tok.accessor *> nameBase)

nameBase =   (Name.VarName  <$> varOp)
         <|> (Name.TypeName <$> Tok.conIdent)


accE      = try( (\id a b -> label id $ Expr.Accessor a b) <$> nextID <*> accBaseE) -- needed by the syntax [1..10]







parensE p = Tok.parens (p <|> (labeled (Expr.Tuple <$> pure []))) -- checks for empty tuple

callList     p = Tok.parens (sepBy p Tok.separator)
callTermE p = (\id a b-> label id (Expr.app b a)) <$ lastLexemeEmpty <*> nextID <*> callList (appArg p)


entBaseE        = entConsE entComplexE
pEntBaseSimpleE = entConsE entSimpleE

entConsE base = choice [ try $ labeled (Expr.Grouped <$> parensE (tlExpr base))
                       , base
                       ]

entComplexE = choice[ --labeled (Expr.Decl <$> labeled decl) -- FIXME: zrobic subparsowanie!
                    entSimpleE
                    ]
             <?> "expression term"

entSimpleE = choice[ caseE -- CHECK [wd]: removed try
                   --, condE
                   , labeled $ Expr.Grouped <$> parensE expr
                   , identE
                   --, try (labeled Expr.RefType <$  Tok.ref <*> Tok.conIdent) <* Tok.accessor <*> varOp
                   , labeled $ Expr.Ref     <$  Tok.ref <*> entSimpleE
                   , labeled $ Expr.Lit     <$> literal
                   , labeled $ listE
                   --, labeled $ Expr.Native  <$> nativeE
                   ]
           <?> "expression term"

optableE = [ 
           --, [ prefixM   "@"  (appID Expr.Ref)                                  ]
             --[ binaryM   ""   (callBuilder <$> genID <*> genID)    AssocLeft ]
             [ operator4 "^"                                  AssocLeft ]
           , [ operator4 "*"                                  AssocLeft ]
           , [ operator4 "/"                                  AssocLeft ]
           , [ operator4 "+"                                  AssocLeft ]
           , [ operator4 "-"                                  AssocLeft ]
           , [ operator4 "<"                                  AssocLeft ]
           , [ operator4 ">"                                  AssocLeft ]
           , [ operator4 "=="                                 AssocLeft ]
           , [ operator4 "in"                                 AssocLeft ]
           , [ binaryM   "$"  (callBuilder <$> nextID)       AssocLeft ]
           , [ postfixM  "::" ((\id a b -> label id (Expr.Typed a b)) <$> nextID <*> typeT) ]
           ]
           where
              --operator op = binaryM op (binaryMatchE <$> (appID Expr.Infix <*> pure op))
              --operator op = binaryM op (binaryMatchE <$> (appID Expr.Infix <*> pure op))
              --operator4 op = binaryM op ( (\id1 id2 l r -> label id1 $ Expr.appInfix (label id2 $ Expr.Var $ NamePath.single $ op) l [r]
              --                            ) <$> nextID <*> nextID)

              --FIXME[wd]: remove fromText call after moving Tokenizer to Text
              operator4 op = binaryM (fromText op) ( (\id1 id2 l r -> label id1 $ Expr.appInfix (label id2 $ Expr.Var $ Expr.Variable (vname $ NamePath.single op) ()) (Expr.unnamed l) [Expr.unnamed r]
                                                   ) <$> nextID <*> nextID)
              --operator op = binaryM op (binaryMatchE <$> (appID Expr.Infix <*> pure ('~':op)))
              --operator2 op = binaryM op (binaryMatchE <$>  ( appID Expr.App <*> (appID Expr.Accessor <*> pure "add" <*> ... ) )  )
              --operator2 op = binaryM op ( (\id1 id2 x y -> Expr.App id1 (Expr.Accessor id2 op x) [y]) <$> genID <*> genID)
              --operator3 op = binaryM op ( (\id1 id2 x y -> Expr.App id1 (Expr.Accessor id2 "contains" y) [x]) <$> genID <*> genID)

--callBuilder id src@(Label lab expr) arg = label id $ case expr of
--    Expr.App src' (Expr.Seq args) -> Expr.App src' (Expr.Seq $ args ++ [Expr.Unnamed arg])
--    _                             -> Expr.App src (Expr.Seq $ [Expr.Unnamed arg])

--callBuilder2 src@(Label lab expr) argsx = case expr of
--    Expr.App src' (Expr.Seq args) -> Expr.App src' (Expr.Seq $ args ++ argsx)
--    _                             -> Expr.App src  (Expr.Seq argsx)

callBuilder id src@(Label lab expr) arg = label id $ case expr of
    Expr.App app -> Expr.App $ NamePat.appendLastSegmentArgs args app
    _             -> Expr.app src args
    where args = [Expr.unnamed arg]

callBuilder2 src@(Label lab expr) args = case expr of
    Expr.App app -> Expr.App $ NamePat.appendLastSegmentArgs args app
    _             -> Expr.app src args

--callBuilder id id2 src arg = case arg of
--    Expr.App id' src' args -> Expr.App id' src (Arg.Named id2 "X!" src' : args)
--    _                      -> Expr.App id src [Arg.Named id2 "Y" arg]

--binaryM2  name fun assoc = PExpr.Infix   (L.reserved name *>        fun) assoc

--binaryMatchE  f p q = f   (Expr.aftermatch p) (Expr.aftermatch q)

--withReservedWords words p = do
--    mapStateVal $ State.addReserved words
--    ret <- p
--    mapStateVal $ State.delReserved words
--    return ret


-- OLDER:
--mkFuncParser func defparser = case name of
--    (Name base segments) -> multiparser
--    _                          -> defparser
--    where name          = Expr._fname func
--          argExpr       = argE expr
--          exprApp p a b = (:) <$> p <* a <*> b
--          segParsers    = fmap (Tok.symbol) segments
--          argParser     = foldr (exprApp argExpr) ((:[]) <$> argExpr) segParsers
--          (Name base segments) = name
--          multiparser   = withReservedWords segments $ tok (Expr.app <$> tok (pure $ Expr.var fname) <*> argParser)
--          [s1,s2] = fmap Tok.symbol segments
--          fname = if null segments then base 
--                                   else base ++ " " ++ join " " segments

-- NEWER:
--mkFuncParser func = State.withReserved (segNames segments) $ tok (Expr.app <$> tok (pure $ Expr.funcVar name) <*> argParser)
--mkFuncParser func = State.withReserved (segNames segments) $  labeled (Expr.App <$> labeled (pure $ Expr.Var name) <*> (Expr.Seq <$> argParser))
--    where name          = Name.fromName $ Decl._fname func
--          argExpr       = argE expr
--          exprApp a b   = (++) <$> a <*> b
--          segParsers    = fmap segParser segments
--          argParser     = foldr exprApp (pure []) segParsers
--          (NamePath base segments) = name

--          segParser seg = case seg of
--              NamePath.Hole    -> (:[]) <$> argExpr
--              NamePath.Token s -> []    <$  Tok.symbol s

--          segNames = segNames' []
--          segNames' names s = case s of
--              []   -> names
--              x:xs -> case x of
--                  NamePath.Token n -> segNames' (n:names) xs
--                  NamePath.Hole    -> segNames' names     xs


-- parse all patterns starting with the longest match and going down
-- if everything fails, try parsing again the longest one to show nice error message
mkFuncParsers (a:as) x =   try (foldl (\a b -> try a <|> b) (mkFuncParser x a) (fmap (mkFuncParser x) as))
                       <|> mkFuncParser x a -- nice error messages
    

appArg p = try (Expr.AppArg <$> just Tok.varIdent <* Tok.assignment <*> p) <|> (Expr.AppArg Nothing <$> p)

mkFuncParser baseVar (id, mpatt) = case mpatt of
    Nothing                                       -> baseVar
    Just patt@(NamePat.NamePatDesc pfx base segs) -> ParserState.withReserved segNames 
                                                   $ labeled $ Expr.App <$> pattParser
        where NamePat.SegmentDesc baseName baseDefs = base
              segParser (NamePat.SegmentDesc name defs) = NamePat.Segment <$> Tok.symbol name <*> defsParser defs
              argExpr         = appArg pEntBaseSimpleE
              segNames        = NamePat.segmentNames patt
              pattParser      = NamePat Nothing <$> baseParser   <*> mapM segParser segs
              baseParser      = NamePat.Segment <$> baseMultiVar <*> defsParser baseDefs
              baseMultiVar    = labeled . pure $ Expr.Var $ Expr.Variable (vname $ NamePat.toNamePath patt) ()
              defsParser defs = fmap takeJustArgs $ mapM argParser defs
              takeJustArgs    = fmap fromJust . filter isJust 
              argParser req   = if req then just  argExpr
                                       else maybe argExpr


notReserved p = do
    rsv  <- view ParserState.adhocReserved <$> get
    name <- p
    if name `elem` rsv then fail $ fromText $ "'" <> name <> "' is a reserved word"
                       else return name


---
varE   = do
    name <- try $ notReserved Tok.varIdent
    ast  <- lookupAST name
    case ast of
        Just possibleDescs -> mkFuncParsers possibleDescs (labeled . pure $ Expr.Var $ Expr.Variable (vname $ NamePath.single name) ())
        Nothing            -> withLabeled $ \id -> do
                                  let np = NamePath.single name
                                  path <- ParserState.getModPath
                                  Namespace.regVarName (OriginInfo path id) np
                                  return $ Expr.Var $ Expr.Variable (vname np) ()



lookupAST name = do
    scope      <- ParserState.getScope
    structInfo <- ParserState.getStructInfo
    pid        <- ParserState.getPid
    --pragmaSet <- view (ParserState.conf . Config.pragmaSet) <$> get
    let argPatts = view StructInfo.argPats structInfo

    case Map.lookup pid scope of
            Nothing                    -> fail "Internal parser error [1]"
            Just (StructInfo.Scope varnames typenames) -> do
                let possibleElems = reverse $ sortBy (compare `on` (length . fst))
                                  $ MapForest.subElems name varnames
                    possibleIDs   = fmap (view StructInfo.target . snd) possibleElems
                    possiblePatts = fmap (flip Map.lookup argPatts) possibleIDs
                    possibleDescs = zip possibleIDs possiblePatts

                case possibleDescs of
                    [] -> if (name == "self")
                          then return Nothing
                          else fail . fromText $ "name '" <> name <> "' is not defined" <> msgTip
                               where scopedNames = "self" : ((fmap $ mjoin " ") $ MapForest.keys varnames)
                                     simWords    = findSimWords name scopedNames
                                     msgTip      = if length simWords > 0 then ", perhaps you ment one of {" <> mjoin ", " (fmap (fromString . show) simWords) <> "}"
                                                                          else ""
                    x  -> return $ Just x




editCosts = EditCosts { deletionCosts      = ConstantCost 10
                      , insertionCosts     = ConstantCost 10
                      , substitutionCosts  = ConstantCost 10
                      , transpositionCosts = ConstantCost 10
                      }

editCosts2 = EditCosts { deletionCosts     = ConstantCost 10
                      , insertionCosts     = ConstantCost 1
                      , substitutionCosts  = ConstantCost 10
                      , transpositionCosts = ConstantCost 3
                      }

findSimWords word words = fmap snd simPairs
    --where dist a b = levenshteinDistance editCosts (phonix a) (phonix b)
    where dist a b = levenshteinDistance editCosts2 (toString a) (toString b)
          simWords = fmap (dist word) words
          simPairs = filter ((<20).fst) 
                   $ List.sortBy (compare `on` fst) 
                   $ zip simWords words


    
--varE   = appID $ Expr.var <*> Tok.varIdent
varOpE = labeled $ (Expr.Var . (flip Expr.Variable ()) . vname . NamePath.single)  <$> try (Tok.parens varOp)
conE   = labeled $ Expr.Cons <$> Tok.conIdent

identE = choice [ varE
                , varOpE
                , conE
                ]

---



listE = Expr.List <$> Tok.brackets listTypes

listTypes = choice [ try $ Expr.RangeList <$> rangeList opE
                   ,       Expr.SeqList   <$> sepBy opE Tok.separator
                   ]

rangeList p =   (Expr.Geometric <$> p <* Tok.range <*> p <*> endLimit)
            <|> (Expr.Linear    <$> p <*> endLimit)
            where endLimit = try (Tok.range *> just p) <|> pure Nothing

caseE     = labeled (Expr.Case <$ Tok.kwCase <*> pEntBaseSimpleE <*> (blockBegin caseBodyE <|> return []))
caseBodyE = labeled (Expr.Match <$> pattern <*> exprBlock)


--condE     = appID Expr.Cond <* Tok.kwIf <*> exprSimple <*> exprBlock <*> maybe (indBlockSpacesIE *> Tok.kwElse *> exprBlock)


            --nativeE     = Tok.betweenNative (many nativeElemE)
            --nativeElemE = choice [ nativeVarE
            --                     , nativeCodeE
            --                     ]
            --nativeCodeE = appID Expr.NativeCode <*> ((:) <$> (noneOf "`#") <*> nativeCodeBodyE)
            --nativeVarE  = appID Expr.NativeVar  <*  symbol "#{" <*> many (noneOf "}") <* symbolic '}'

            --nativeCodeBodyE = (try(lookAhead $ string "#{")  *> pure [])
            --              <|> (try(lookAhead $ string "```") *> pure [])
            --              <|> ((++) <$> ((:) <$> anyChar <*> many (noneOf "`#")) <*> nativeCodeBodyE)


exprBlock  = blockBegin expr


----------------------------------------------------------------------
-- Code segments
----------------------------------------------------------------------
--indBlockBody   p = many1 (Indent.checkIndentedOrEq *> p <* indBlockSpaces)

--indBlockSpaces   = try (Tok.spaces <* Indent.checkIndent) <|> pure mempty

moduleBlock p = braceBlockBegin p <|> indBlockBody p
blockBegin  p = indBlockBegin   p <|> braceBlockBegin p

indBlockBegin  p = Tok.indBlockBegin *> indBlock p
indBlock       p = Tok.spaces *> Indent.indented *> Indent.withPos (indBlockBody p)
indBlockBody   p = (:) <$> p <*> many (indBlockPrefix p)
indBlockBody'  p = (:) <$> p <*> many (try $ indBlockPrefix p)
indBlockBodyOpt p = ($) <$> (((:) <$> p) <|> pure id) 
                        <*> many (indBlockPrefix p)
indBlockPrefix p = try ((try (Tok.spaces *> Indent.checkIndent) <|> try (Tok.terminator *> Tok.spaces *> Indent.checkIndentedOrEq )) *> notFollowedBy eof) *> p
--indBlockBody   p = (:) <$> p <*> many (try (Tok.spaces *> Indent.checkIndent) *> p)
indBlockSpacesIE = try (Tok.spaces <* Indent.checkIndentedOrEq) <|> pure mempty

braceBlockBegin p = Tok.braceL *> Tok.spaces *> Indent.withDiscarded (many1 (p <* braceBlockSpaces)) <* Tok.braceR
braceBlockSpaces  = Tok.terminator *> Tok.spaces

codeBlock    p = indCodeBlock p -- <|> braceCodeBlock p
indCodeBlock p = indCodeBlockStart *> indBlockBody p <* indBlockEnd

indCodeBlockStart = Tok.indBlockBegin *> indBlockStart
indBlockStart     = Tok.spaces *> Indent.indented *> Indent.startBlock
indBlockEnd       = Indent.endBlock

blockStart  = indCodeBlockStart
blockEnd    = indBlockEnd
blockBody p = indBlockBody p
blockBody' p = indBlockBody' p
blockBodyOpt p = indBlockBodyOpt p


blockBeginFields p = Tok.indBlockBegin *> indBlockFields p
indBlockFields   p = Tok.spaces *> Indent.indented *> Indent.withPos (indBlockBodyFields p)
indBlockBodyFields   p = (:) <$> p <*> many (indBlockPrefixFields p)
indBlockPrefixFields p = ((try (Tok.spaces *> Indent.checkIndentedOrEq)) *> notFollowedBy eof) *> p


-----------------------------------------------------------
-- Utils
-----------------------------------------------------------

parserName = "Luna Compiler"

run p st = evalStateT (Indent.parser p) st

handleResult r = case r of
    Failure e -> Left e
    Success a -> Right a

bundleResult p = (,) <$> p <*> get

end = (Tok.spaces <?> "") <* (eof <?> "")

upToEnd p = Tok.spaces *> p <* end

renderErr e = renderPretty 0.8 80 $ e Leijen.<> linebreak

-----------------------------------------------------------
-- Pragmas
-----------------------------------------------------------

appConf = Config.registerPragma (undefined :: Pragma.TabLength)
        . Config.registerPragma (undefined :: Pragma.AllowOrphans)
        . Config.registerPragma (undefined :: Pragma.ImplicitSelf)

-- FIXME[wd]: logika powina byc przeniesiona na system pluginow
defConfig = appConf def
-- FIXME[wd]: debugowo ustawione wartosci typow
emptyState = def :: ParserState ()
defState  = emptyState & ParserState.conf .~ defConfig


appSt = ParserState.conf %~ appConf

--st = def {State._conf = conf}

-----------------------------------------------------------
-- Section parsing
-----------------------------------------------------------
-- Usage example: parseExpr (fileFeed "test.txt")
parseGen p st = run (bundleResult (unit p)) st
parseGen2 p st = run (bundleResult p) st

--moduleParser modPath = parseGen (upToEnd $ func)
moduleParser modPath = parseGen (upToEnd $ pUnit $ pModule (last modPath) (init modPath))
--exprParser           = parseGen (upToEnd expr)
exprBlockParser      = parseGen (upToEnd $ indBlock expr)
exprBlockParser2     = parseGen2 (upToEnd $ indBlock expr)
exprParser2          = parseGen2 (upToEnd expr)
--patternParser        = parseGen (upToEnd pattern)
--typeParser           = parseGen (upToEnd typeT)

-----------------------------------------------------------
-- Input utils
-----------------------------------------------------------

parserDelta name = Directed (UTF8.fromString name) 0 0 0 0

parseFromByteString = Trifecta.parseByteString

parseFromText p delta txt = Trifecta.parseByteString p delta (convert $ Text.encodeUtf8 txt)

parseFromString p delta input = parseFromByteString p delta (UTF8.fromString input)

parseFromFile p delta path = do
  s <- liftIO $ ByteStr.readFile path
  return $ parseFromByteString p delta s

parseFile       path  p = handleResult <$> parseFromFile       p (parserDelta parserName) path
parseString     input p = handleResult  $  parseFromString     p (parserDelta parserName) input
parseByteString input p = handleResult  $  parseFromByteString p (parserDelta parserName) input

parseByteString2 p input = handleResult  $  parseFromByteString p (parserDelta parserName) input
parseText2 p input = handleResult  $  parseFromText p (parserDelta parserName) input
                --data AliasAnalysis = AliasAnalysis

                --traverseM        = AST.traverseM        AliasAnalysis
                --defaultTraverseM = AST.defaultTraverseM AliasAnalysis

testme ast st = ast -- runState (traverseM ast) st


                ----type AACtx m lab e a conf v = (Enumerated lab, TLSet.Lookup conf (Pragma.Pragma Pragma.AllowOrphans),
                ----                              MonadState (State a e v conf) m, Show conf, Show v, Show e, Show a, Functor m) 

                --type AACtx m lab e s conf v = (Enumerated lab, MonadState (State s e v conf) m, Applicative m)

                --instance (AACtx m lab e s conf v, AST.Traversal AliasAnalysis m a a)
                --    => AST.Traversal AliasAnalysis m (LModule lab a) (LModule lab a) where
                --    traverseM _ = aatest

                --instance (AACtx m lab e s conf v, AST.Traversal AliasAnalysis m a a)
                --      => AST.Traversal AliasAnalysis m (LDecl lab a) (LDecl lab a) where
                --    traverseM _ = traverseDecl

                --instance AACtx m lab e s conf v
                --      => AST.Traversal AliasAnalysis m (LPat lab) (LPat lab) where
                --    traverseM _ = registerPat



                --aaunit (Unit mod) = Unit <$> aatest mod

                --aatest mod@(Label lab (Module path name body)) = State.withNewScope id continue
                --        where continue =  registerDecls body
                --                       *> defaultTraverseM mod
                --              id       = Enum.id lab


                --registerDecls decls =  mapM registerHeaders  decls
                --                    *> mapM registerDataDecl decls


                --registerDataDecl (Label lab decl) = case decl of
                --    Decl.Data     name _ cons defs   -> State.withNewScope id (registerDecls defs) *> pure ()
                --    _                                -> pure ()
                --    where id = Enum.id lab

                --registerHeaders (Label lab decl) = case decl of
                --    Decl.Function _ name inputs _ _  -> State.regVarName id (view NamePath.base name)
                --                                     <* State.withNewScope id (traverseM inputs)
                --    Decl.Data     name _ cons _      -> State.regTypeName id (Name.fromName name) 
                --                                     <* mapM_ registerCons cons
                --    _                                -> pure ()
                --    where id = Enum.id lab

                --registerPat p@(Label lab pat) = case pat of
                --    Pat.Var         name       -> State.regVarName id (Name.fromName name) *> continue
                --    _                          -> continue
                --    where id = Enum.id lab
                --          continue = defaultTraverseM p 

                --registerCons (Label lab (Decl.Cons name fields)) = State.regVarName (Enum.id lab) (Name.fromName name)


                --traverseDecl d@(Label lab decl) = case decl of
                --    Decl.Function path name inputs output body -> State.withNewScope id $ defaultTraverseM d
                --    _ -> continue
                --    where id       = Enum.id lab
                --          continue = defaultTraverseM d


                --traverseDecl2Pass (Label lab decl) = fmap (Label lab) $ case decl of
                --    Decl.Function path name inputs output body -> do
                --        subAST  <- subparse (unlines body)
                --        inputs' <- mapM subparseArg inputs
                --        return $ Decl.Function path name inputs' output subAST
                --    Decl.Data        name params cons defs -> return $ Decl.Data        name params [] []
                --    Decl.Import      path rename targets   -> return $ Decl.Import      path rename targets
                --    Decl.TypeAlias   dst src               -> return $ Decl.TypeAlias   dst src
                --    Decl.TypeWrapper dst src               -> return $ Decl.TypeWrapper dst src
                --    where id = Enum.id lab
                --          subparse expr = do 
                --              result <- State.withScope id (parseString expr <$> (exprBlockParser2 <$> get))
                --              case result of
                --                  Left e      -> fail   $ show e
                --                  Right (e,_) -> return $ e
                --          -- FIXME [wd]: inny parser powinine parsowac argumenty poniewaz nie zawieraja wielu linii i nie moga zawierac wielu exproessionow!
                --          --             zatem wyciaganie pierwszego elementu jest szybkim obejsciem
                --          subparseArg (Arg pat val) = Arg pat . (fmap (!!0)) <$> mapM subparse val 




--registerClassHeaders (Label lab decl) = case decl of
--    Decl.Data       cls cons _ _ -> register' id cls cons
--    where id = Enum.id lab
--          register' id cls cons = State.regTypeName name id -- <* mapM registerConsHeaders cons
--                                  where name = view Type.name cls


    --instance (MonadState (State.State a) m, Enumerated lab) => AST.Traversal AliasAnalysis m (Label lab (Module f e)) where
    --    traverse base x@(Label lab m) = State.withNewScope id continue
    --        where continue = AST.defaultTraverse base x
    --              id       = Enum.id lab

    --instance (MonadState (State.State a) m, Enumerated lab) 
    --         => AST.Traversal AliasAnalysis m (Label lab (Decl.Decl f e)) where
    --    traverse base x@(Label lab ast) = case ast of
    --        --Decl.Function path name inputs output body -> State.regVarName id (view NamePath.base name) *> State.withNewScope id continue
    --        --_                                          -> continue
    --        _                                          -> undefined
    --        where continue = AST.defaultTraverse base x
    --              id       = Enum.id lab


--s2Decl d = case Label.element d of
--    Decl.Function path name inputs output body -> State.regVarName id (view Name.base name) *> 
--    where id = Label.label d

--    | Function    { _path    :: Path    , _fname    :: NamePath  , _inputs  :: [Arg f e]   , _output :: Maybe (RType f) , _body :: [e] }



    --vaMod :: Module -> VAPass StructInfo
    --vaMod el@(Module.Module id cls imports classes typeAliases typeDefs fields methods modules) = do
    --    regModule el
    --    withScope id $ regVarName name id *> continue
    --    getAliasInfo
    --    where name     = el ^. Module.cls ^. Type.name
    --          continue =  pure ()
    --                   -- -- <* mapM registerDataCons classes -- register just data constructors before functions
    --                   <* mapM registerFuncHeaders methods
    --                   <* mapM registerClassHeaders classes

    --                   <* vaType cls
    --                   <* fexpMap imports
    --                   <* fexpMap classes -- register class functions before data member functions
    --                   <* fexpMap typeAliases
    --                   <* fexpMap typeDefs
    --                   <* fexpMap fields
    --                   <* fexpMap methods
    --                   <* fmodMap modules
    --          fexpMap  = mapM vaExpr
    --          fmodMap  = mapM vaMod


    ----registerDataCons :: Expr.Expr -> VAPass ()
    ----registerDataCons el = VAState.regExpr el *> case el of
    ----    --Expr.Data       {} -> withID continue
    ----    --Expr.ConD       {} -> regParentVarName name id *> continue
    ----    _                  -> continue
    ----    where continue = Expr.traverseM_ registerDataCons vaType vaPat vaLit el
    ----          withID   = VAState.withID (el ^. Expr.id)
    ----          id       = el ^.  Expr.id
    ----          name     = el ^.  Expr.name

    --registerClassHeaders :: Expr.Expr -> VAPass ()
    --registerClassHeaders cls = case cls of
    --    Expr.Data       id cls cons _ _ -> register' id cls cons
    --    Expr.DataNative id cls cons _ _ -> register' id cls cons
    --    where register' id cls cons = regTypeName name id <* mapM registerConsHeaders cons
    --                                  where name = view Type.name cls

    --registerConsHeaders :: Expr.Expr -> VAPass ()
    --registerConsHeaders (Expr.ConD id name fields) = regVarName name id



    --registerFuncHeaders :: Expr.Expr -> VAPass ()
    --registerFuncHeaders el = regExpr el *> case el of
    --    Expr.Function   id _ name _ _ _ -> regVarName (Name.unified name) id
    --    where continue = Expr.traverseM_ registerFuncHeaders vaType vaPat vaLit pure el