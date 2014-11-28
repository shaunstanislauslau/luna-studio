---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2014
---------------------------------------------------------------------------
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE ViewPatterns              #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE TypeOperators             #-}

module Flowbox.Geom2D.Rasterizer (
    module Flowbox.Geom2D.Rasterizer,
    Point2(..)
) where

import           Data.Array.Accelerate ((&&*), (||*), (==*), (>*))
import qualified Data.Array.Accelerate as A
import           Data.Array.Accelerate.IO
import           Data.Bits                  ((.&.))
import           Data.Maybe
import           Data.VectorSpace
import           Diagrams.Backend.Cairo
import           Diagrams.Backend.Cairo.Internal
import           Diagrams.Segment
import           Diagrams.Prelude hiding (Path)
import           Graphics.Rendering.Cairo hiding (translate, Path)
import           System.IO.Unsafe

import           Math.Coordinate.Cartesian (Point2(..))
import           Flowbox.Geom2D.Accelerate.QuadraticBezier.Solve
import           Flowbox.Geom2D.ControlPoint
import           Flowbox.Geom2D.CubicBezier
import           Flowbox.Geom2D.Mask
import           Flowbox.Geom2D.Path
import           Flowbox.Geom2D.QuadraticBezier
import           Flowbox.Geom2D.QuadraticBezier.Conversion
import qualified Flowbox.Graphics.Image.Channel as Channel
import           Flowbox.Graphics.Image.Image   (Image)
import qualified Flowbox.Graphics.Image.Image as Image
import           Flowbox.Graphics.Image.IO.BMP
import qualified Flowbox.Graphics.Image.View    as View
import qualified Flowbox.Graphics.Utils as U
import           Flowbox.Math.Matrix (Matrix(..), Matrix2, Z(..), DIM2, (:.)(..))
import qualified Flowbox.Math.Matrix as M
import           Flowbox.Prelude hiding ((#), use)



-- intended to be hidden from this package
f2d :: Real a => a -> Double
f2d = fromRational . toRational

unpackP :: Num a => Maybe (Point2 a) -> Point2 a
unpackP = fromMaybe (Point2 0 0)

makeSegments :: Real a => Bool -> [ControlPoint a] -> [Segment Closed R2]
makeSegments closed points = combine points
    where combine []  = []
          combine [a'] = if not closed then [] else let
                  ControlPoint (Point2 ax ay) _ b' = f2d' a'
                  ControlPoint (Point2 dx dy) c' _ = f2d' $ head points
                  Point2 bx by = unpackP b'
                  Point2 cx cy = unpackP c'
                  a = r2 (ax , ay)
                  b = r2 (bx , by)
                  c = r2 (cx , cy)
                  d = r2 (dx , dy)
              in [bezier3 b (d ^+^ c ^-^ a) (d ^-^ a)]
          combine (a':d':xs) = let
                  ControlPoint (Point2 ax ay) _ b' = f2d' a'
                  ControlPoint (Point2 dx dy) c' _ = f2d' d'
                  Point2 bx by = unpackP b'
                  Point2 cx cy = unpackP c'
                  a = r2 (ax , ay)
                  b = r2 (bx , by)
                  c = r2 (cx , cy)
                  d = r2 (dx , dy)
              in bezier3 b (d ^+^ c ^-^ a) (d ^-^ a) : combine (d':xs)
          combine _ = error "Flowbox.Geom2D.Rasterizer.makeSegments: unsupported ammount of points"
          f2d' = fmap f2d

--makeCubics :: Real a => [ControlPoint a] -> [CubicBezier a]
makeCubics :: Real a => Path a -> [CubicBezier a]
makeCubics (Path closed points) = combine points
    where combine [] = []
          combine [a'] = if not closed then [] else let
                  ControlPoint a _ (unpackP -> b) = a'
                  ControlPoint d (unpackP -> c) _ = head points
              in [CubicBezier a (a+b) (d+c) d]
          combine (a':d':xs) = let
                  ControlPoint a _ (unpackP -> b) = a'
                  ControlPoint d (unpackP -> c) _ = d'
              in CubicBezier a (a+b) (d+c) d : combine (d':xs)
          combine _ = error "Flowbox.Geom2D.Rasterizer.makeCubics: unsupported ammount of points"

pathToRGBA32 :: Real a => Int -> Int -> Path a -> A.Array DIM2 RGBA32
pathToRGBA32 w h (Path closed points) = unsafePerformIO rasterize
    where ControlPoint (Point2 ox oy) _ _ = fmap f2d $ head points
          h' = fromIntegral h
          rasterize = do
              let path = fromSegments $ makeSegments closed points
                  diagram = case closed of
                      False -> path                        # translate (r2 (ox,oy)) # scaleY (-1) # translateY h' # lc white # lw (Output 1)
                      True  -> (strokeLoop.closeLine) path # translate (r2 (ox,oy)) # scaleY (-1) # translateY h' # fc white # lw (Output 0)
                  (_, r) = renderDia Cairo (CairoOptions "" (Dims (fromIntegral w) (fromIntegral h)) RenderOnly True) (diagram :: Diagram Cairo R2)
              surface <- createImageSurface FormatARGB32 w h
              renderWith surface r
              bs <- imageSurfaceGetData surface
              fromByteString (Z:.h:.w) ((), bs)

pathToMatrix :: Real a => Int -> Int -> Path a -> Matrix2 Double
pathToMatrix w h path = extractArr $ pathToRGBA32 w h path
    where extractArr arr = Delayed $ A.map extractVal $ A.use arr
          extractVal :: M.Exp RGBA32 -> M.Exp Double
          extractVal rgba = (A.fromIntegral $ (rgba `div` 0x1000000) .&. 0xFF) / 255

rasterizeMask :: Real a => Int -> Int -> Mask a -> Matrix2 Double
rasterizeMask w h (Mask path' feather') = path
    --case feather' of
    --    Nothing -> path
    --    Just feather' -> let
    --            feather = ptm feather'
    --            convert :: Real a => Path a -> A.Acc (A.Vector (QuadraticBezier Double))
    --            convert p = let
    --                    a = makeCubics p
    --                in A.use $ A.fromList (Z :. length a) $ convertCubicsToQuadratics 5 0.001 $ (fmap.fmap) f2d a
    --            cA = convert path'
    --            cB = convert feather'
    --        in M.generate (A.index2 (U.variable h) (U.variable w)) $ combine feather cA cB
    where ptm  = pathToMatrix w h
          path = ptm path'
          combine :: Matrix2 Double -> A.Acc (A.Vector (QuadraticBezier Double)) -> A.Acc (A.Vector (QuadraticBezier Double)) -> A.Exp A.DIM2 -> A.Exp Double
          combine feather pQ fQ idx@(A.unlift . A.unindex2 -> (A.fromIntegral -> y, A.fromIntegral -> x) :: (A.Exp Int, A.Exp Int)) = let
                  p  = path M.! idx
                  f  = feather M.! idx
                  d  = distanceFromQuadratics (A.lift $ Point2 x y)
                  dp = d pQ
                  df = d fQ
              in A.cond ((p >* 0 &&* f >* 0) ||* (p ==* 0 &&* f ==* 0)) p (dp / (dp+df) * p)

matrixToImage :: Matrix2 Double -> Image View.RGBA
matrixToImage a = Image.singleton view
    where view = View.append (Channel.ChannelFloat "r" $ Channel.FlatData w)
               $ View.append (Channel.ChannelFloat "g" $ Channel.FlatData w)
               $ View.append (Channel.ChannelFloat "b" $ Channel.FlatData w)
               $ View.append (Channel.ChannelFloat "a" $ Channel.FlatData a)
               $ View.empty "rgba"
          w = M.map (\_ -> 1) a
