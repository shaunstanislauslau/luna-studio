---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2013
---------------------------------------------------------------------------
{-# LANGUAGE DeriveGeneric #-}

module Flowbox.Data.Version where

import           Flowbox.Prelude   
import           GHC.Generics      
import           Data.Aeson        
import           Data.Default                              (Default, def)

data Version = Version { branch :: [Int]
                       , tags   :: [String]
                       } deriving (Read, Show, Eq, Generic)

-------------------------------------------------
-- INSTANCES
-------------------------------------------------

instance Default Version where
    def = Version { branch = [0,1,0]
                  , tags   = def
                  }

instance ToJSON Version
instance FromJSON Version

