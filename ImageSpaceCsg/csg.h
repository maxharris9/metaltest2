//
//  csg.h
//  XXX
//
//  Created by Max Harris on 6/4/16.
//  Copyright © 2016 Max Harris. All rights reserved.
//

typedef enum {
  ADD,
  SUBTRACT,
  INTERSECT,
  LEAF
} csgOperation;

class shape {
public:
  shape () {}
  ~shape () {}
};

class csgNode {
public:
  csgOperation operation;
  csgNode *leftChild;
  csgNode *rightChild;
  shape *shape;
  csgNode (csgOperation op, csgNode *lc, csgNode *rc) {
    operation = op;
    leftChild = lc;
    rightChild = rc;
  }
  bool hasChildren () {
    return (this->leftChild != NULL || this->rightChild != NULL);
  }
  void setShape (class shape &sh) {
    this->shape = &sh;
  }
  ~csgNode () {}
};

class csgTree {
public:
  csgNode *rootNode;
  csgTree (csgNode &node);
  ~csgTree ();
  bool replaceSetEquivalences(csgNode &node);
  csgNode *normalize(csgNode *node);
};