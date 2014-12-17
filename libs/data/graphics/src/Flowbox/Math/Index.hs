---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2014
---------------------------------------------------------------------------
{-# LANGUAGE ConstraintKinds        #-}
{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TypeFamilies           #-}

module Flowbox.Math.Index where

import           Flowbox.Graphics.Prelude as P
import qualified Data.Array.Accelerate    as A

import Math.Coordinate.Cartesian hiding (x, y)
import Math.Space.Space          hiding (height, width)



-- == Boundable class
class Boundable a b c | a -> b c where
    unsafeIndex2D  :: a -> Point2 b -> c
    boundary       :: a -> Grid b

-- Boundable matrix
data BMatrix m a = BMatrix { container :: m a
                           , canvas :: A.DIM2
                           }

boundedIndex2D :: ( Boundable a b c, Integral b, Ord b
                  , Condition b, Condition c, Boolean b ~ Boolean c, Logical (Boolean c)
                  ) => A.Boundary c -> a -> Point2 b -> c
boundedIndex2D b obj (Point2 x y) = case b of
    A.Clamp      -> getter $ Point2 ((x `min` maxX) `max` 0) ((y `min` maxY) `max` 0)
    A.Wrap       -> getter $ Point2 (x `mod` width) (y `mod` height) 
    A.Constant a -> if' (x > maxX || x < 0 || y > maxY || y < 0) a $ getter $ Point2 x y
    A.Mirror     -> error "Not implemented yet" -- TODO [KL]
    where Grid width height = boundary obj
          getter            = unsafeIndex2D obj
          maxX = width  - 1
          maxY = height - 1
