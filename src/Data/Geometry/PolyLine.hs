{-# LANGUAGE TemplateHaskell  #-}
{-# LANGUAGE DeriveFunctor  #-}
{-# LANGUAGE UndecidableInstances  #-}
module Data.Geometry.PolyLine where

import           Control.Lens
import           Data.Bifunctor
import           Data.Ext
import qualified Data.Foldable as F
import           Data.Geometry.Box
import           Data.Geometry.LineSegment
import           Data.Geometry.Point
import           Data.Geometry.Properties
import           Data.Geometry.Transformation
import           Data.Geometry.Vector
import           Data.LSeq (LSeq, pattern (:<|))
import qualified Data.LSeq as LSeq
import qualified Data.List.NonEmpty as NE
import           GHC.TypeLits

--------------------------------------------------------------------------------
-- * d-dimensional Polygonal Lines (PolyLines)

-- | A Poly line in R^d has at least 2 vertices
newtype PolyLine d p r = PolyLine { _points :: LSeq 2 (Point d r :+ p) }
makeLenses ''PolyLine

deriving instance (Show r, Show p, Arity d) => Show    (PolyLine d p r)
deriving instance (Eq r, Eq p, Arity d)     => Eq      (PolyLine d p r)
deriving instance (Ord r, Ord p, Arity d)   => Ord     (PolyLine d p r)

instance Arity d => Functor (PolyLine d p) where
  fmap f (PolyLine ps) = PolyLine $ fmap (first (fmap f)) ps

type instance Dimension (PolyLine d p r) = d
type instance NumType   (PolyLine d p r) = r

instance Semigroup (PolyLine d p r) where
  (PolyLine pts) <> (PolyLine pts') = PolyLine $ pts <> pts'

instance Arity d => IsBoxable (PolyLine d p r) where
  boundingBox = boundingBoxList . NE.fromList . toListOf (points.traverse.core)

instance (Fractional r, Arity d, Arity (d + 1)) => IsTransformable (PolyLine d p r) where
  transformBy = transformPointFunctor

instance PointFunctor (PolyLine d p) where
  pmap f = over points (fmap (first f))

instance Arity d => Bifunctor (PolyLine d) where
  bimap f g (PolyLine pts) = PolyLine $ fmap (bimap (fmap g) f) pts


-- | pre: The input list contains at least two points
fromPoints :: [Point d r :+ p] -> PolyLine d p r
fromPoints = PolyLine . LSeq.forceLSeq (C  :: C 2) . LSeq.fromList

-- | pre: The input list contains at least two points. All extra vields are
-- initialized with mempty.
fromPoints' :: (Monoid p) => [Point d r] -> PolyLine d p r
fromPoints' = fromPoints . map (\p -> p :+ mempty)


-- | We consider the line-segment as closed.
fromLineSegment                     :: LineSegment d p r -> PolyLine d p r
fromLineSegment ~(LineSegment' p q) = fromPoints [p,q]

-- | Convert to a closed line segment by taking the first two points.
asLineSegment                            :: PolyLine d p r -> LineSegment d p r
asLineSegment (PolyLine (p :<| q :<| _)) = ClosedLineSegment p q

-- | Stricter version of asLineSegment that fails if the Polyline contains more
-- than two points.
asLineSegment'                :: PolyLine d p r -> Maybe (LineSegment d p r)
asLineSegment' (PolyLine pts) = case F.toList pts of
                                  [p,q] -> Just $ ClosedLineSegment p q
                                  _     -> Nothing
