bool isBitSet(int b, int pos) => (b & (1 << pos)) != 0;

int setBit(int b, int pos) => (b | 1 << pos);

int unsetBit(int b, int pos) => (b & ~(1 << pos));
