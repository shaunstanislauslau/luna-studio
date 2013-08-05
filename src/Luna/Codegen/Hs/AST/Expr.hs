---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2013
---------------------------------------------------------------------------

module Luna.Codegen.Hs.AST.Expr (
    Expr(..),
    Context(..),
    genCode,
    mkAlias,
    mkCall,
    mkPure,
    addExpr,
    mkBlock,
    empty
)where

import           Data.String.Utils                 (join)
import qualified Luna.Codegen.Hs.Path            as Path
--import qualified Luna.Codegen.Hs.GenState         as GenState
--import           Luna.Codegen.Hs.GenState           (GenState)

data Context = Pure | IO deriving (Show, Eq)

data Expr = Assignment { src   :: Expr    , dst  :: Expr   , ctx :: Context }
          | Var        { name  :: String                                    }
          | VarRef     { vid   :: Int                                       } 
          | Tuple      { elems :: [Expr]                                    }
          | NTuple     { elems :: [Expr]                                    }
          | Call       { name  :: String  , args :: [Expr] , ctx :: Context }
          | Default    { val   :: String                                    }
          | THExprCtx  { name  :: String                                    }
          | THTypeCtx  { name  :: String                                    }
          | Cons       { name  :: String  , fields :: [Expr]                }
          | Typed      { src   :: Expr    , t :: String                     }
          | At         { name  :: String  , dst :: Expr                     }
          | Any        {                                                    }
          | Block      { body  :: [Expr]                                    }
          | BlockRet   { name  :: String  , ctx :: Context                  }
          | NOP        {                                                    }
          deriving (Show)


empty :: Expr
empty = NOP

mpostfix :: String
mpostfix = "''M"


mkBlock :: String -> Expr
mkBlock retname = Block [BlockRet retname IO]


genCode :: Expr -> String
genCode expr = case expr of
    Assignment src' dst' ctx'   -> genCode src' ++ " " ++ operator ++ " " ++ genCode dst' where
                                   operator = case ctx' of
                                       Pure -> "="
                                       IO   -> "<-"
    Var        name'            -> name'
    Default    val'             -> val'
    VarRef     vid'             -> "v'" ++ show vid'
    Call       name' args' ctx' -> fname' ++ " " ++ join " " (map (genCode) args') where
                                   fname' = case ctx' of
                                       Pure -> name'
                                       IO   -> name' ++ mpostfix
    Tuple      elems'           -> if length elems' == 1
                                     then "OneTuple " ++ body
                                     else "(" ++ body ++ ")"
                                         where body = join ", " (map (genCode) elems')
    NTuple     elems'           -> "(" ++ join ", (" (map (genCode) elems') ++ ", ()" ++ replicate (length elems') ')'
    THExprCtx  name'            -> "'"  ++ name'
    THTypeCtx  name'            -> "''" ++ name'
    Cons       name' fields'    -> name' ++ " {" ++ join ", " (map genCode fields') ++ "}"
    Typed      src' t'          -> genCode src' ++ " :: " ++ t'
    At         name' dst'       -> name' ++ "@" ++ genCode dst'
    Any                         -> "_"
    Block      body'            -> genBlockCode body' IO
    BlockRet   name' ctx'       -> case ctx' of
                                       Pure -> "in " ++ name'
                                       IO   -> "return " ++ name'
    NOP                         -> ""


genBlockCode :: [Expr] -> Context -> String
genBlockCode exprs' ctx' = case exprs' of
    []     -> ""
    x : xs -> prefix ++ indent ++ genCode x ++ "\n" ++ genBlockCode xs ectx where
        ectx = ctx x
        indent = case x of
            BlockRet{} -> Path.mkIndent 1
            _          -> case ectx of
                              Pure -> Path.mkIndent 2
                              _    -> Path.mkIndent 1
        prefix = if ctx' == IO && ectx == Pure
            then Path.mkIndent 1 ++ "let\n"
            else ""


addExpr :: Expr -> Expr -> Expr
addExpr nexpr base = base { body = nexpr : body base }

mkPure :: Expr -> Expr
mkPure expr = case expr of
    Assignment src' dst' _   -> Assignment (mkPure src') (mkPure dst') Pure
    Tuple      elems'        -> Tuple $ map mkPure elems'
    Call       name' args' _ -> Call name' (map mkPure args') Pure
    Block      body'         -> Block (map mkPure body')
    BlockRet   name' ctx'    -> BlockRet name' Pure
    other                    -> other


mkAlias :: (String, String) -> Expr
mkAlias (n1, n2) = Assignment (Var n1) (Var n2) Pure


mkCall :: String -> [String] -> Expr
mkCall name' args' = Call name' (map Var args') Pure