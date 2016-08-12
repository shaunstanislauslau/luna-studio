{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns      #-}

module Reactive.Commands.CommandSearcher.Commands
    ( toggleText
    , querySearchCmd
    , queryTreeCmd
    , runCommand
    , help
    ) where

import qualified Data.Map                             as Map
import           Data.Text.Lazy                       (stripPrefix)
import qualified Data.Text.Lazy                       as Text
import           Utils.PreludePlus                    hiding (Item, stripPrefix)
import           Utils.Vector

import qualified Batch.Workspace                      as Workspace
import qualified Reactive.Commands.Batch              as BatchCmd
import qualified Empire.API.Data.Project              as Project
import           Event.Event                          (JSState)
import qualified JS.GoogleAnalytics                   as GA
import qualified JS.NodeSearcher                      as UI
import           Reactive.Commands.Command            (Command, performIO)
import qualified Reactive.Commands.Camera             as Camera
import           Reactive.Commands.NodeSearcher       as NS
import           Reactive.Commands.ProjectManager     (loadProject)
import qualified Reactive.State.Camera                as Camera
import qualified Reactive.State.Global                as Global
import qualified Reactive.State.UIElements            as UIElements
import           Text.ScopeSearcher.Item              (Item (..))
import qualified Text.ScopeSearcher.Scope             as Scope


commands :: Command Global.State ([(Text, Item)])
commands = do
    projects <- uses (Global.workspace . Workspace.projects) Map.elems
    gaState  <- uses Global.jsState gaEnabled
    let projectToItem p = (name, Element) where name = Text.pack $ p ^. Project.name
        projectList = Map.fromList $ projectToItem <$> projects
        projectCmd  = Map.fromList [ ("new",    Element)
                                   , ("export", Element)
                                   , ("open",   Group projectList)
                                   -- , ("rename", Element)
                                   ]
        settingsCmd = Map.fromList [gaElement]
        gaElement   = if gaState then ("disableGoogleAnalytics", Element)
                                 else ("enableGoogleAnalytics", Element)
    return [ ("project",          Group projectCmd)
           , ("insert",           Element)
           , ("help",             Element)
           , ("toggleTextEditor", Element)
           , ("settings",         Group settingsCmd)
           ]


createProject :: Text -> Command Global.State ()
createProject name = BatchCmd.createProject name

openProject :: Text -> Command Global.State ()
openProject name = do
    projs <- use $ Global.workspace . Workspace.projects
    let mayProject = find (\(_,p) -> p ^. Project.name == (Text.unpack name)) (Map.toList projs)
    case mayProject of
        Just (projectId, project) -> loadProject projectId
        Nothing                   -> performIO $ putStrLn "Project not found"



help :: Command Global.State ()
help = do
    GA.sendEvent $ GA.OpenHelp
    performIO $ openHelp'

toggleText :: Command Global.State ()
toggleText = do
    GA.sendEvent $ GA.ToggleText
    Global.uiElements . UIElements.textEditorVisible %= not
    size <- use $ Global.camera . Camera.camera . Camera.windowSize
    Camera.updateWindowSize size

foreign import javascript unsafe "$('.tutorial-box').show().focus()"    openHelp'  :: IO ()
foreign import javascript unsafe "common.enableGA($1)"    enableGA' :: Bool -> IO ()
foreign import javascript unsafe "$1.isGAEnabled()"       gaEnabled :: JSState -> Bool

enableGA :: Bool -> Command a ()
enableGA val = do
    GA.sendEvent $ GA.GAOptOut val
    performIO $ enableGA' val


runCommand :: Text -> Command Global.State ()
runCommand "project.new"                              = performIO $ UI.initNodeSearcher "project.new untitled" Nothing (Vector2 200 200) True
runCommand (stripPrefix "project.new "  -> Just name) = createProject name
runCommand (stripPrefix "project.open." -> Just name) = openProject name
runCommand "project.export"                           = exportCurrentProject
runCommand "help"                                     = help
runCommand "insert"                                   = NS.openFresh
runCommand "toggleTextEditor"                         = toggleText
runCommand "settings.disableGoogleAnalytics"          = enableGA False
runCommand "settings.enableGoogleAnalytics"           = enableGA True
runCommand cmd                                        = performIO $ putStrLn $ "Unknown command " <> (Text.unpack cmd)

querySearchCmd :: Text -> Command Global.State ()
querySearchCmd query = do
    sd <- commands
    let sd'   = Map.fromList sd
        items = Scope.searchInScope sd' query
    performIO $ UI.displayQueryResults UI.CommandSearcher items

queryTreeCmd :: Text -> Command Global.State ()
queryTreeCmd query = do
    sd <- commands
    let sd'   = Map.fromList sd
        items = Scope.moduleItems sd' query
    performIO $ UI.displayTreeResults UI.CommandSearcher items


exportCurrentProject :: Command Global.State ()
exportCurrentProject = (use $ Global.workspace . Workspace.currentProjectId) >>= BatchCmd.exportProject
