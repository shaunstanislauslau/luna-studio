{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE TemplateHaskell    #-}

module ZMQ.Bus.Control.Handler.ID where

import qualified Data.IORef                      as IORef

import           Flowbox.Prelude
import           Flowbox.System.Log.Logger
import           ZMQ.Bus.Control.BusCtx          (BusCtx)
import qualified ZMQ.Bus.Control.BusCtx          as BusCtx
import           ZMQ.Bus.Control.Handler.Methods
import           ZMQ.RPC.RPC                     (RPC)



logger :: LoggerIO
logger = getLoggerIO $moduleName

-------- public api -------------------------------------------------

create :: BusCtx -> Methods -> RPC Results
create ctx CreateID = do
    logger info "called ID::create"
    let senderID = BusCtx.nextSenderID ctx
    liftIO $ IORef.atomicModifyIORef senderID
                                     (\i -> let newID = i + 1
                                            in (newID, CreateIDResult newID))
