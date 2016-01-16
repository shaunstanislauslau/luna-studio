{-# LANGUAGE OverloadedStrings #-}

module Empire.Server.Library where

import           Prologue

import qualified Data.Binary                      as Bin
import           Control.Monad.State              (StateT)
import           Data.ByteString                  (ByteString)
import           Data.ByteString.Lazy             (fromStrict, toStrict)
import qualified Flowbox.Bus.Data.Flag            as Flag
import qualified Flowbox.Bus.Data.Message         as Message
import qualified Flowbox.Bus.Bus                  as Bus
import           Flowbox.Bus.BusT                 (BusT (..))
import qualified Flowbox.System.Log.Logger        as Logger
import qualified Empire.Env                       as Env
import           Empire.Env                       (Env)
import qualified Empire.Data.Library              as DataLibrary
import qualified Empire.API.Library.CreateLibrary as CreateLibrary
import qualified Empire.API.Library.ListLibraries as ListLibraries
import qualified Empire.API.Update                as Update
import qualified Empire.API.Topic                 as Topic
import qualified Empire.Commands.Library          as Library
import qualified Empire.Empire                    as Empire
import           Empire.Server.Server             (sendToBus, errorMessage)

logger :: Logger.LoggerIO
logger = Logger.getLoggerIO $(Logger.moduleName)

handleCreateLibrary :: ByteString -> StateT Env BusT ()
handleCreateLibrary content = do
    let request = Bin.decode . fromStrict $ content :: CreateLibrary.Request
    currentEmpireEnv <- use Env.empireEnv
    (result, newEmpireEnv) <- liftIO $ Empire.runEmpire currentEmpireEnv $ Library.createLibrary
        (request ^. CreateLibrary.projectId)
        (request ^. CreateLibrary.libraryName)
        (fromString $ request ^. CreateLibrary.path)
    case result of
        Left err -> logger Logger.error $ errorMessage <> err
        Right (libraryId, library) -> do
            Env.empireEnv .= newEmpireEnv
            let update = Update.Update request $ CreateLibrary.Result libraryId $ DataLibrary.toAPI library
            sendToBus Topic.createLibraryUpdate update

handleListLibraries :: ByteString -> StateT Env BusT ()
handleListLibraries content = do
    let request = Bin.decode . fromStrict $ content :: ListLibraries.Request
    currentEmpireEnv <- use Env.empireEnv
    (result, newEmpireEnv) <- liftIO $ Empire.runEmpire currentEmpireEnv $ Library.listLibraries
        (request ^. ListLibraries.projectId)
    case result of
        Left err -> logger Logger.error $ errorMessage <> err
        Right librariesList -> do
            Env.empireEnv .= newEmpireEnv
            let update = Update.Update request $ ListLibraries.Status $ (_2 %~ DataLibrary.toAPI) <$> librariesList
            sendToBus Topic.listLibrariesStatus update
