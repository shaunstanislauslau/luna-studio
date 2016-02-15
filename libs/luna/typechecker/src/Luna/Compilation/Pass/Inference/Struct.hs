{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE CPP                       #-}

module Luna.Compilation.Pass.Inference.Struct where

import Prelude.Luna

import Data.Construction
import Data.Prop
import Data.Record
import Data.Graph.Builder
import Luna.Evaluation.Runtime                      (Static, Dynamic)
import Luna.Syntax.AST.Term                         hiding (source)
import Luna.Syntax.Model.Layer
import Luna.Syntax.Model.Network.Builder.Node
import Luna.Syntax.Model.Network.Builder.Term.Class (runNetworkBuilderT, NetGraph, NetLayers)
import Luna.Syntax.Model.Network.Class              ()
import Luna.Syntax.Model.Network.Term
import Luna.Syntax.Name.Ident.Pool                  (MonadIdentPool, newVarIdent')
import Type.Inference

import qualified Luna.Compilation.Stage.TypeCheck as TypeCheck
import qualified Luna.Syntax.Name                 as Name
import Data.Graph.Backend.VectorGraph


#define PassCtx(m,ls,term) ( term ~ Draft Static               \
                           , ne   ~ Link (ls :< term)          \
                           , Prop Type   (ls :< term) ~ Ref Edge ne \
                           , BiCastable     e ne                     \
                           , BiCastable     n (ls :< term)           \
                           , MonadBuilder  (Hetero (VectorGraph n e)) m                \
                           , HasProp Type     (ls :< term)     \
                           , NodeInferable  m (ls :< term)     \
                           , TermNode Var   m (ls :< term)     \
                           , TermNode Lam   m (ls :< term)     \
                           , TermNode Unify m (ls :< term)     \
                           , TermNode Acc   m (ls :< term)     \
                           , MonadIdentPool m                  \
                           )


buildAppType :: (PassCtx(m,ls,term), nodeRef ~ Ref Node (ls :< term)) => nodeRef -> m [nodeRef]
buildAppType appRef = do
    appNode <- read appRef
    caseTest (uncover appNode) $ do
        match $ \(App srcConn argConns) -> do
            src      <- follow source srcConn
            args     <- mapM2 (follow source) argConns
            specArgs <- mapM2 getTypeSpec args
            out      <- var' =<< newVarIdent'
            l        <- lam' specArgs out

            src_v    <- read src
            let src_tc = src_v # Type
            src_t    <- follow source src_tc
            uniSrcTp <- unify src_t l
            reconnect src (prop Type) uniSrcTp

            app_v    <- read appRef
            let app_tc = app_v # Type
            app_t    <- follow source app_tc
            uniAppTp <- unify app_t out
            reconnect appRef (prop Type) uniAppTp

            return [uniSrcTp, uniAppTp]

        match $ \ANY -> impossible


buildAccType :: (PassCtx(m,ls,term), nodeRef ~ Ref Node (ls :< term)) => nodeRef -> m [nodeRef]
buildAccType accRef = do
    appNode <- read accRef
    caseTest (uncover appNode) $ do
        match $ \(Acc name srcConn) -> do
            src      <- follow source srcConn
            srcTSpec <- getTypeSpec src
            newType  <- acc name srcTSpec
            acc_v    <- read accRef
            let acc_tc = acc_v # Type
            acc_t    <- follow source acc_tc
            uniTp    <- unify acc_t newType
            reconnect accRef (prop Type) uniTp
            return [uniTp]
        match $ \ANY -> impossible


-- | Returns a concrete type of a node
--   If the type is just universe, create a new type variable
getTypeSpec :: PassCtx(m,ls,term) => Ref Node (ls :< term) -> m (Ref Node (ls :< term))
getTypeSpec ref = do
    val <- read ref
    tp  <- follow source $ val # Type
    if tp /= universe then return tp else do
        ntp <- var' =<< newVarIdent'
        reconnect ref (prop Type) ntp
        return ntp

run :: (PassCtx(m,ls,term), nodeRef ~ Ref Node (ls :< term)) => [nodeRef] -> [nodeRef] -> m [nodeRef]
run apps accs = do
    appUnis <- concat <$> mapM buildAppType apps
    accUnis <- concat <$> mapM buildAccType accs
    return $ appUnis <> accUnis -- FIXME[WD]: use monadic element registration instead



universe = Ref 0 -- FIXME [WD]: Implement it in safe way. Maybe "star" should always result in the top one?