---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2013
---------------------------------------------------------------------------
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE TemplateHaskell #-}

module Flowbox.Luna.Data.AST.Module where

import           Flowbox.Prelude                 hiding (id, drop, mod, Traversal)
import qualified Flowbox.Luna.Data.AST.Expr      as Expr
import           Flowbox.Luna.Data.AST.Expr        (Expr)
import qualified Flowbox.Luna.Data.AST.Type      as Type
import           Flowbox.Luna.Data.AST.Type        (Type)
import qualified Flowbox.Luna.Data.AST.Lit       as Lit
import           Flowbox.Luna.Data.AST.Lit         (Lit)
import qualified Flowbox.Luna.Data.AST.Pat       as Pat
import           Flowbox.Luna.Data.AST.Pat         (Pat)
import           Flowbox.Luna.Data.AST.Utils       (ID)
import           GHC.Generics                      (Generic)
import           Flowbox.Generics.Deriving.QShow   
import           Control.Applicative               

type Traversal m = (Functor m, Applicative m, Monad m)

data Module = Module { _id      :: ID
                     , _cls     :: Type     
                     , _imports :: [Expr] 
                     , _classes :: [Expr] 
                     , _fields  :: [Expr] 
                     , _methods :: [Expr] 
                     , _modules :: [Module] 
                     } deriving (Show, Generic)

instance QShow Module
makeLenses (''Module)


mk :: ID -> Type -> Module
mk id' mod = Module id' mod [] [] [] [] []

mkClass :: Module -> Expr
mkClass (Module id' (Type.Module tid path) _ classes' fields' methods' _) = 
    Expr.Class id' (Type.Class tid (last path) []) classes' fields' methods'

addMethod :: Expr -> Module -> Module
addMethod method mod = mod & methods %~ (method:)

addField :: Expr -> Module -> Module
addField field mod = mod & fields %~ (field:)

addClass :: Expr -> Module -> Module
addClass ncls mod = mod & classes %~ (ncls:)

addImport :: Expr -> Module -> Module
addImport imp mod = mod & imports %~ (imp:)


traverseM :: Traversal m => (Module -> m Module) -> (Expr -> m Expr) -> (Type -> m Type) -> (Pat -> m Pat) -> (Lit -> m Lit) -> Module -> m Module
traverseM fmod fexp ftype _{-fpat-} _{-flit-} mod = case mod of
    Module     id' cls' imports' classes'             
               fields' methods' modules'     ->  Module id' 
                                                 <$> ftype cls' 
                                                 <*> fexpMap imports' 
                                                 <*> fexpMap classes' 
                                                 <*> fexpMap fields' 
                                                 <*> fexpMap methods' 
                                                 <*> fmodMap modules'
    where fexpMap = mapM fexp
          fmodMap = mapM fmod

traverseM_ :: Traversal m => (Module -> m a) -> (Expr -> m b) -> (Type -> m c) -> (Pat -> m d) -> (Lit -> m e) -> Module -> m ()
traverseM_ fmod fexp ftype _{-fpat-} _{-flit-} mod = case mod of
    Module     _ cls' imports' classes'             
               fields' methods' modules'     -> drop 
                                                <* ftype cls' 
                                                <* fexpMap imports'
                                                <* fexpMap classes' 
                                                <* fexpMap fields' 
                                                <* fexpMap methods' 
                                                <* fmodMap modules'
    where drop    = pure ()
          fexpMap = mapM_ fexp
          fmodMap = mapM_ fmod


--traverseM' :: Traversal m => (Expr -> m Expr) -> Module -> m Module
--traverseM' fexp mod = traverseM fexp pure pure pure mod


--traverseM'_ :: Traversal m => (Expr -> m ()) -> Module -> m ()
--traverseM'_ fexp mod = traverseM_ fexp pure pure pure mod