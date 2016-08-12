module Reactive.Plugins.Core.Action.Navigation where


import           Data.List (maximumBy)
import           Data.Function (on)
import qualified Data.HashMap.Strict               as HashMap

import           Utils.PreludePlus
import           Utils.Vector

import           Object.Widget                     (WidgetFile, WidgetId, objectId, widget, Position)
import qualified Object.Widget.Node                as Model

import           Event.Event                       (Event (Mouse, Keyboard), JSState)
import           Event.Keyboard                    (KeyMods (..), shift)
import qualified Event.Keyboard                    as Keyboard
import qualified Event.Mouse                       as Mouse

import           Reactive.State.Global             (State, inRegistry)
import qualified Reactive.State.Global             as Global
import qualified Reactive.State.UIRegistry         as UIRegistry
import qualified Reactive.State.Graph              as Graph

import qualified Empire.API.Data.Node              as N
import qualified Empire.API.Data.PortRef           as R
import qualified Empire.API.Data.Port              as P
import qualified Empire.API.Data.Connection        as C

import           Reactive.Commands.Command         (Command, performIO)
import           Reactive.Commands.Graph           (allNodes)
import           Reactive.Commands.Graph.Selection (focusSelectedNode, selectAll, selectedNodes, unselectAll)
import qualified Reactive.Commands.UIRegistry      as UICmd
import           Reactive.Commands.Batch           (collaborativeTouch, cancelCollaborativeTouch)



toAction :: Event -> Maybe (Command State ())
toAction (Keyboard _ (Keyboard.Event Keyboard.Down char (KeyMods True False False False))) = case char of
    '\t'  -> Just goPrev
    '\37' -> Just goPrev
    '\39' -> Just goNext
    _     -> Nothing
toAction (Keyboard _ (Keyboard.Event Keyboard.Down char (KeyMods False False False False))) = case char of
    '\37' -> Just goLeft
    '\39' -> Just goRight
    '\38' -> Just goUp
    '\40' -> Just goDown
    _     -> Nothing
toAction (Keyboard _ (Keyboard.Event Keyboard.Down char (KeyMods True True False False))) = case char of
    '\37' -> Just goConeLeft
    '\39' -> Just goConeRight
    '\38' -> Just goConeUp
    '\40' -> Just goConeDown
    _     -> Nothing
toAction _ = Nothing

goPrev, goNext :: Command State ()
goPrev = do
    nodes <- allNodes
    let selectedNodes = findSelected nodes
    when (not $ null selectedNodes) $ do
        let nodeSrc = findLeftMost selectedNodes
            nodeId = nodeSrc ^. widget . Model.nodeId
            inPortRefSelf      = R.InPortRef nodeId P.Self
            inPortRefFirstPort = R.InPortRef nodeId $ P.Arg 0
        prevSelfNodeIdMay <- preuse $ Global.graph . Graph.connectionsMap . ix inPortRefSelf . C.src . R.srcNodeId
        case prevSelfNodeIdMay of
            Just prevSelfNodeId -> goToNodeId selectedNodes prevSelfNodeId
            Nothing -> do
                prevFirstPortNodeIdMay <- preuse $ Global.graph . Graph.connectionsMap . ix inPortRefFirstPort . C.src . R.srcNodeId
                withJust prevFirstPortNodeIdMay $ \prevFirstPortNodeId -> goToNodeId selectedNodes prevFirstPortNodeId
goNext = do
    nodes <- allNodes
    let selectedNodes = findSelected nodes
    when (not $ null selectedNodes) $ do
        let nodeSrc = findRightMost selectedNodes
            nodeId = nodeSrc ^. widget . Model.nodeId
        nextNodeIds <- getDstNodeIds nodeId
        nextNodes <- catMaybes <$> mapM toWidgetFile nextNodeIds
        when (not $ null nextNodes) $ do
            let nextNode = findUpMost nextNodes
            changeSelection selectedNodes nextNode

getDstNodeIds :: N.NodeId -> Command State [N.NodeId]
getDstNodeIds nodeId = do
    connMap <- use $ Global.graph . Graph.connectionsMap
    let connections = filter matchNodeId $ HashMap.elems connMap
    return $ (^. C.dst . R.dstNodeId) <$> connections
    where
        matchNodeId conn = conn ^. C.src . R.srcNodeId == nodeId

toWidgetFile :: N.NodeId -> Command State (Maybe (WidgetFile Model.Node))
toWidgetFile nodeId = do
    widgetIdMay <- preuse $ Global.graph . Graph.nodeWidgetsMap . ix nodeId
    nodeMayMay <- inRegistry $ mapM lookupNode widgetIdMay
    return $ join nodeMayMay

-- TODO: merge with MultiSelection.hs
lookupNode :: WidgetId -> Command UIRegistry.State (Maybe (WidgetFile Model.Node))
lookupNode = UIRegistry.lookupTypedM

goToNodeId :: [WidgetFile Model.Node] -> N.NodeId -> Command State ()
goToNodeId selectedNodes nodeId = do
    widgetIdMay <- preuse $ Global.graph . Graph.nodeWidgetsMap . ix nodeId
    withJust widgetIdMay $ \widgetId -> do
        changeSelection' selectedNodes nodeId widgetId

goRight, goLeft, goDown, goUp :: Command State ()
goRight = go findRightMost findNodesOnRightSide findNearestRight
goLeft  = go findLeftMost  findNodesOnLeftSide  findNearestLeft
goDown  = go findDownMost  findNodesOnDownSide  findNearestDown
goUp    = go findUpMost    findNodesOnUpSide    findNearestUp

go :: ([WidgetFile Model.Node] -> WidgetFile Model.Node) ->
      (Position -> [WidgetFile Model.Node] -> [WidgetFile Model.Node]) ->
      (Position -> [WidgetFile Model.Node] -> WidgetFile Model.Node) ->
      Command State ()
go findMost findNodesOnSide findNearest = do
    nodes <- allNodes
    let selectedNodes = findSelected nodes
    when (not $ null selectedNodes) $ do
        let nodeSrc = findMost selectedNodes
            pos = nodeSrc ^. widget . Model.position
            nodesSide = findNodesOnSide pos nodes
        when (not $ null nodesSide) $ do
            let nearest = findNearest pos nodesSide
            changeSelection selectedNodes nearest

closenestPow = 3.0

axisDistanceRight :: Vector2 Double -> Double
axisDistanceRight (Vector2 x y) =  x
axisDistanceLeft  (Vector2 x y) = -x
axisDistanceDown  (Vector2 x y) =  y
axisDistanceUp    (Vector2 x y) = -y

findNearestRight, findNearestLeft, findNearestDown, findNearestUp :: Position -> [WidgetFile Model.Node] -> WidgetFile Model.Node
findNearestRight pos = maximumBy (compare `on` (closenest pos axisDistanceRight))
findNearestLeft  pos = maximumBy (compare `on` (closenest pos axisDistanceLeft))
findNearestDown  pos = maximumBy (compare `on` (closenest pos axisDistanceDown))
findNearestUp    pos = maximumBy (compare `on` (closenest pos axisDistanceUp))

closenest :: Position -> (Vector2 Double -> Double) -> WidgetFile Model.Node -> Double
closenest pos axisDistance wf = axisDist / (dist ** closenestPow) where
    pos' = wf ^. widget . Model.position
    vect = pos' - pos
    dist = magnitude vect
    axisDist = axisDistance vect

goConeRight, goConeLeft, goConeDown, goConeUp :: Command State ()
goConeRight = goCone findRightMost findNodesOnRight findNodesOnRightSide
goConeLeft  = goCone findLeftMost  findNodesOnLeft  findNodesOnLeftSide
goConeDown  = goCone findDownMost  findNodesOnDown  findNodesOnDownSide
goConeUp    = goCone findUpMost    findNodesOnUp    findNodesOnUpSide

goCone :: ([WidgetFile Model.Node] -> WidgetFile Model.Node) ->
          (Position -> [WidgetFile Model.Node] -> [WidgetFile Model.Node]) ->
          (Position -> [WidgetFile Model.Node] -> [WidgetFile Model.Node]) ->
          Command State ()
goCone findMost findNodesInCone findNodesOnSide = do
    nodes <- allNodes
    let selectedNodes = findSelected nodes
    when (not $ null selectedNodes) $ do
        let nodeSrc = findMost selectedNodes
            pos = nodeSrc ^. widget . Model.position
            nodesCone = findNodesInCone pos nodes
            nodesSide = findNodesOnSide pos nodes
        if not $ null nodesCone
            then                               changeSelection selectedNodes $ findNearestNode pos nodesCone
            else when (not $ null nodesSide) $ changeSelection selectedNodes $ findNearestNode pos nodesSide

findRightMost, findLeftMost, findDownMost, findUpMost :: [WidgetFile Model.Node] -> WidgetFile Model.Node
findRightMost = maximumBy (compare `on` (^. widget . Model.position . x))
findLeftMost  = minimumBy (compare `on` (^. widget . Model.position . x))
findDownMost  = maximumBy (compare `on` (^. widget . Model.position . y))
findUpMost    = minimumBy (compare `on` (^. widget . Model.position . y))

findNodesOnRightSide, findNodesOnLeftSide, findNodesOnDownSide, findNodesOnUpSide :: Position -> [WidgetFile Model.Node] -> [WidgetFile Model.Node]
findNodesOnRightSide pos = filter $ \wf -> wf ^. widget . Model.position . x > pos ^. x
findNodesOnLeftSide  pos = filter $ \wf -> wf ^. widget . Model.position . x < pos ^. x
findNodesOnDownSide  pos = filter $ \wf -> wf ^. widget . Model.position . y > pos ^. y
findNodesOnUpSide    pos = filter $ \wf -> wf ^. widget . Model.position . y < pos ^. y

findNodesOnRight, findNodesOnLeft, findNodesOnDown, findNodesOnUp :: Position -> [WidgetFile Model.Node] -> [WidgetFile Model.Node]
findNodesOnRight = filter . isOnRight
findNodesOnLeft  = filter . isOnLeft
findNodesOnDown  = filter . isOnDown
findNodesOnUp    = filter . isOnUp

isOnRight, isOnLeft, isOnDown, isOnUp :: Position -> WidgetFile Model.Node -> Bool
isOnRight = isInCone (>)  skip (>=)
isOnLeft  = isInCone (<)  skip (>=)
isOnDown  = isInCone skip (>)  (<)
isOnUp    = isInCone skip (<)  (<)

skip :: Double -> Double -> Bool
skip _ _ = True

isInCone :: (Double -> Double -> Bool) -> (Double -> Double -> Bool) -> (Double -> Double -> Bool) -> Position -> WidgetFile Model.Node -> Bool
isInCone cmpDXZero cmpDYZero cmpDims pos wf = dx `cmpDXZero` 0.0 && dy `cmpDYZero` 0.0 && abs dx `cmpDims` abs dy where
    nodePos = wf ^. widget . Model.position
    dx = nodePos ^. x - pos ^. x
    dy = nodePos ^. y - pos ^. y

findSelected :: [WidgetFile Model.Node] -> [WidgetFile Model.Node]
findSelected = filter $ \wf -> wf ^. widget . Model.isSelected

findNearestNode :: Position -> [WidgetFile Model.Node] -> WidgetFile Model.Node
findNearestNode pos = minimumBy (compare `on` (distance pos))

distance :: Position -> WidgetFile Model.Node -> Double
distance pos wf = lengthSquared (wpos - pos) where
    wpos = wf ^. widget . Model.position

changeSelection :: [WidgetFile Model.Node] -> WidgetFile Model.Node -> Command State ()
changeSelection selectedNodes node = do
    unselectNodes selectedNodes
    selectNode node

changeSelection' :: [WidgetFile Model.Node] -> N.NodeId -> WidgetId -> Command State ()
changeSelection' selectedNodes nodeId widgetId = do
    unselectNodes selectedNodes
    selectNode' nodeId widgetId

unselectNodes :: [WidgetFile Model.Node] -> Command State ()
unselectNodes selectedNodes = do
    inRegistry $ forM selectedNodes $ \node -> UICmd.update_ (node ^. objectId) $ Model.isSelected .~ False
    cancelCollaborativeTouch $ (^. widget . Model.nodeId) <$> selectedNodes

selectNode :: WidgetFile Model.Node -> Command State ()
selectNode node = selectNode' (node ^. widget . Model.nodeId) (node ^. objectId)

selectNode' :: N.NodeId -> WidgetId -> Command State ()
selectNode' nodeId widgetId = do
    inRegistry $ UICmd.update_ widgetId $ Model.isSelected .~ True
    collaborativeTouch [nodeId]
