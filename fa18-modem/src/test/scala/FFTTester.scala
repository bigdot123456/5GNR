package modem

import dsptools.DspTester

import breeze.math.Complex

/**
 * DspTester for FFT
 */
class FFTTester[T <: chisel3.Data](c: FFT[T], inp: Seq[Complex], out: Seq[Complex], pktStart: Boolean = true, pktEnd: Boolean = true, tolLSBs: Int = 5) extends DspTester(c) with HasTesterUtil[FFT[T]] {
  val maxCyclesWait = scala.math.max(50, c.params.numPoints * 3)

  poke(c.io.out.ready, 0)
  poke(c.io.in.valid, 0)
  step(1)
  poke(c.io.out.ready, 1)

  inp.zipWithIndex.foreach { case (value, index) =>
    poke(c.io.in.valid, 1)
    poke(c.io.in.bits.iq(0), value)
    poke(c.io.in.bits.pktStart, (pktStart && (index == 0)))
    poke(c.io.in.bits.pktEnd  , (pktEnd && (index == inp.length - 1)))
    wait_for_assert(c.io.in.ready, maxCyclesWait)
    step(1)
    poke(c.io.in.bits.pktStart, 0)
    poke(c.io.in.bits.pktEnd, 0)
    poke(c.io.in.bits.iq(0), Complex(0, 0))
    poke(c.io.in.valid, 0)
    if (index != inp.length - 1) { step(3) }
  }
  poke(c.io.in.valid, 0)

  wait_for_assert(c.io.out.valid, maxCyclesWait)
  expect(c.io.out.bits.pktStart, pktStart)
  expect(c.io.out.bits.pktEnd  , pktEnd)
  fixTolLSBs.withValue(tolLSBs) { expect_complex_seq(c.io.out.bits.iq, out) }
}

/**
 * DspTester for IFFT
 */
class IFFTTester[T <: chisel3.Data](c: IFFT[T], inp: Seq[Complex], out: Seq[Complex], pktStart: Boolean = true, pktEnd: Boolean = true, tolLSBs: Int = 2) extends DspTester(c) with HasTesterUtil[IFFT[T]] {
  val maxCyclesWait = scala.math.max(50, c.params.numPoints * 3)

  poke(c.io.out.ready, 1)
  poke(c.io.in.valid, 1)

  poke_complex_seq(c.io.in.bits.iq, inp)
  poke(c.io.in.bits.pktStart, pktStart)
  poke(c.io.in.bits.pktEnd  , pktEnd)
  wait_for_assert(c.io.in.ready, maxCyclesWait)

  out.zipWithIndex.foreach { case (value, index) =>
    wait_for_assert(c.io.out.valid, maxCyclesWait)
    expect(c.io.out.bits.pktStart, (pktStart && (index == 0)))
    expect(c.io.out.bits.pktEnd  , (pktEnd && (index == inp.length - 1)))
    fixTolLSBs.withValue(tolLSBs) { expect(c.io.out.bits.iq(0), value) }
    step(1)
  }
}

/**
 * Convenience functions for running tests
 */
object FixedFFTTester {
  def apply(params: FixedFFTParams, inp: Seq[Complex], out: Seq[Complex]): Boolean = {
    dsptools.Driver.execute(() => new FFT(params), TestSetup.dspTesterOptions) { c => new FFTTester(c, inp, out) }
  }
}
object FixedIFFTTester {
  def apply(params: FixedFFTParams, inp: Seq[Complex], out: Seq[Complex]): Boolean = {
    dsptools.Driver.execute(() => new IFFT(params), TestSetup.dspTesterOptions) { c => new IFFTTester(c, inp, out) }
  }
}
