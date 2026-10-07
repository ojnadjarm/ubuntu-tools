/** One linear neuron with a bias: the weight scales the input, the bias (fed by a constant source) shifts the sum. */
export const output = (w: number, x: number, b: number, src = 1): number => w * x + b * src;
