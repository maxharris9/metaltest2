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
    INTERSECT
} csgOperation;

class csgNode {
    public:
    csgOperation operation;
    csgNode *leftChild;
    csgNode *rightChild;
    csgNode (csgOperation op, csgNode *lc, csgNode *rc) {
        operation = op;
        leftChild = lc;
        rightChild = rc;
    }
    bool hasChildren () {
        return (leftChild != NULL || rightChild != NULL);
    }
    ~csgNode () {}
};

class csgTree {
    bool replaceSetEquivalences(csgNode &node);
    csgNode *normalize(csgNode &node);
};