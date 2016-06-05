//
//  csg.mm
//  XXX
//
//  Created by Max Harris on 6/4/16.
//  Copyright © 2016 Max Harris. All rights reserved.
//

#include <stdio.h>
#include "csg.h"

bool csgTree::replaceSetEquivalences(csgNode &node) {
    if (node.operation == ADD) {
        return false;
    }

    csgNode *rightChild = node.rightChild;
    csgNode *X = node.leftChild;
    csgNode *Y = rightChild->leftChild;
    csgNode *Z = rightChild->rightChild;
    if (rightChild->operation == SUBTRACT && rightChild->operation == ADD) {
        node = csgNode(SUBTRACT, new csgNode(SUBTRACT, X, Y), Z);
        return true;
    } else if (rightChild->operation == INTERSECT && rightChild->operation == ADD) {
        node = csgNode(ADD, new csgNode(INTERSECT, X, Y), new csgNode(INTERSECT, X, Z));
        return true;
    } else if (rightChild->operation == SUBTRACT && rightChild->operation == INTERSECT) {
        node = csgNode(ADD, new csgNode(SUBTRACT, X, Y), new csgNode(SUBTRACT, X, Z));
        return true;
    } else if (rightChild->operation == INTERSECT && rightChild->operation == INTERSECT) {
        node = csgNode(INTERSECT, new csgNode(INTERSECT, X, Y), Z);
        return true;
    } else if (rightChild->operation == SUBTRACT && rightChild->operation == SUBTRACT) {
        node = csgNode(ADD, new csgNode(SUBTRACT, X, Y), new csgNode(INTERSECT, X, Y));
        return true;
    } else if (rightChild->operation == INTERSECT && rightChild->operation == SUBTRACT) {
        node = csgNode(SUBTRACT, new csgNode(INTERSECT, X, Y), Z);
        return true;
    }

    csgNode *leftChild = node.leftChild;
    csgNode *x = leftChild->leftChild;
    csgNode *y = leftChild->rightChild;
    csgNode *z = node.rightChild;
    if (leftChild->operation == SUBTRACT && node.operation == INTERSECT) {
        node = csgNode(SUBTRACT, new csgNode(INTERSECT, x, z), y);
        return true;
    } else if (leftChild->operation == ADD && node.operation == SUBTRACT) {
        node = csgNode(ADD, new csgNode(SUBTRACT, x, z), new csgNode(SUBTRACT, y, z));
        return true;
    } else if (leftChild->operation == ADD && node.operation == INTERSECT) {
        node = csgNode(ADD, new csgNode(INTERSECT, x, z), new csgNode(INTERSECT, y, z));
        return true;
    }

    return false;
}

csgNode *csgTree::normalize(csgNode &node) {
    while (this->replaceSetEquivalences(node) && node.hasChildren()) { }
    node.leftChild = this->normalize(*node.leftChild);
    return &node;
}