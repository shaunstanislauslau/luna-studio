---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2013
---------------------------------------------------------------------------
{-# LANGUAGE ConstraintKinds  #-}
{-# LANGUAGE FlexibleContexts #-}

module Flowbox.Luna.Passes.Transform.Graph.Builder.State where

import           Control.Monad.State
import qualified Data.IntMap         as IntMap
import           Data.Map            (Map)
import qualified Data.Map            as Map

import           Flowbox.Control.Error
import           Flowbox.Luna.Data.Analysis.Alias.GeneralVarMap (GeneralVarMap)
import qualified Flowbox.Luna.Data.Analysis.Alias.GeneralVarMap as GeneralVarMap
import qualified Flowbox.Luna.Data.AST.Utils                    as AST
import qualified Flowbox.Luna.Data.Attributes                   as Attributes
import           Flowbox.Luna.Data.Graph.Edge                   (Edge (Edge))
import           Flowbox.Luna.Data.Graph.Graph                  (Graph)
import qualified Flowbox.Luna.Data.Graph.Graph                  as Graph
import           Flowbox.Luna.Data.Graph.Node                   (Node)
import qualified Flowbox.Luna.Data.Graph.Node                   as Node
import           Flowbox.Luna.Data.Graph.Port                   (InPort, OutPort)
import           Flowbox.Luna.Data.PropertyMap                  (PropertyMap)
import qualified Flowbox.Luna.Data.PropertyMap                  as PropertyMap
import qualified Flowbox.Luna.Passes.Transform.Graph.Attributes as Attributes
import           Flowbox.Prelude
import           Flowbox.System.Log.Logger



logger :: Logger
logger = getLogger "Flowbox.Luna.Passes.Transform.Graph.Builder.State"


type NodeMap = Map AST.ID (Node.ID, OutPort)


data GBState = GBState { graph       :: Graph
                       , nodeMap     :: NodeMap
                       , gvmMap      :: GeneralVarMap
                       , propertyMap :: PropertyMap
                       } deriving (Show)


type GBStateM m = MonadState GBState m


make :: GeneralVarMap -> PropertyMap -> GBState
make = GBState Graph.make Map.empty


addToNodeMap :: GBStateM m => AST.ID -> (Node.ID, OutPort) -> m ()
addToNodeMap k v = do nm <- getNodeMap
                      setNodeMap $ Map.insert k v nm


insNode :: GBStateM m => (Node.ID, Node) -> Bool -> Bool -> m ()
insNode n@(nodeID, _) isFolded noAssignment = do 
    g <- getGraph
    setGraph $ Graph.insNode n g
    if isFolded
        then setProperty Attributes.astFolded
        else return ()
    if noAssignment
        then setProperty Attributes.astNoAssignment
        else return ()
    where setProperty key = getPropertyMap >>= setPropertyMap . PropertyMap.set nodeID Attributes.luna key Attributes.true


addNode :: GBStateM m => AST.ID -> OutPort -> Node -> Bool -> Bool -> m ()
addNode astID outPort node isFolded noAssignment = do
    insNode (astID, node) isFolded noAssignment
    addToNodeMap astID (astID, outPort)


connect :: GBStateM m => Node.ID -> Node.ID -> Edge -> m ()
connect srcID dstID edge = getGraph >>= setGraph . Graph.connect srcID dstID edge


connectAST :: GBStateM m => AST.ID -> Node.ID -> InPort -> m ()
connectAST srcID dstNID dstPort = do
    (srcNID, srcPort) <- gvmNodeMapLookUp srcID
    connect srcNID dstNID $ Edge srcPort dstPort


getGraph :: GBStateM m => m Graph
getGraph = get >>= return . graph


setGraph :: GBStateM m => Graph -> m ()
setGraph gr = do s <- get
                 put s { graph = gr }


getNodeMap :: GBStateM m => m NodeMap
getNodeMap = get >>= return . nodeMap


setNodeMap :: GBStateM m => NodeMap -> m ()
setNodeMap nm = do s <- get
                   put s { nodeMap = nm }


getgvmMap :: GBStateM m => m GeneralVarMap
getgvmMap = get >>= return . gvmMap


setgvmMap :: GBStateM m => GeneralVarMap -> m ()
setgvmMap gvm = do s <- get
                   put s { gvmMap = gvm }


getPropertyMap :: GBStateM m => m PropertyMap
getPropertyMap = get >>= return . propertyMap


setPropertyMap :: GBStateM m => PropertyMap -> m ()
setPropertyMap pm = do s <- get
                       put s { propertyMap = pm }


gvmLookUp :: GBStateM m => AST.ID -> m AST.ID
gvmLookUp astID = do gvm <- getgvmMap
                     case IntMap.lookup astID $ GeneralVarMap.varmap gvm of
                        Just (Right a) -> return a
                        _              -> return astID


nodeMapLookUp :: GBStateM m => AST.ID -> m (Node.ID, OutPort)
nodeMapLookUp astID = do nm <- getNodeMap
                         Map.lookup astID nm <?> ("Cannot find " ++ (show astID) ++ " in nodeMap")



gvmNodeMapLookUp :: GBStateM m => AST.ID -> m (Node.ID, OutPort)
gvmNodeMapLookUp astID = gvmLookUp astID >>= nodeMapLookUp
