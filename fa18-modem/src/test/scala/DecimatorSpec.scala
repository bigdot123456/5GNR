package modem

import breeze.math.Complex
import dsptools.numbers._
import chisel3._
import chisel3.experimental.FixedPoint
import org.scalatest.{FlatSpec, Matchers}

case class DecimatorTestVectors() {
  val r = new scala.util.Random
  val bigInputVector: Seq[Complex] =
    Seq.fill(100)(Complex(2*(r.nextFloat)-1, 2*(r.nextFloat)-1))
}

case class FixedDecimationParams(
  // width of I and Q
  iqWidth: Int,
  // Amount to decimate by
  nDecimation: Int
) extends DecimatorParams[FixedPoint] {
  //PacketBundleParams fields
  // prototype for iq
  // binary point is iqWidth-3 to allow for some inflation
  val protoIQ = DspComplex(FixedPoint(iqWidth.W, (iqWidth-3).BP))
  val width = 1
}

class DecimationSpec extends FlatSpec with Matchers {
  val vecs = DecimatorTestVectors()
  behavior of "DecimatebyN"

  val decimateBy10Params = FixedDecimationParams(
    iqWidth = 16,
    nDecimation = 10
  )
  it should "decimate by 10" in {
    val trials = Seq(IQ(vecs.bigInputVector, None))
    FixedDecimationTester(decimateBy10Params, trials) should be (true)
  }

  // val corrParams = FixedPacketDetectParams(
  //   iqWidth = 16,
  //   powerThreshWindow = 4,
  //   correlationThresh = true
  // )
  // it should "detect power and correlation" in {
  //   val trials = Seq(IQ(vecs.tvNoPkt, None),
  //     IQ(vecs.tvPwrOnly, None),
  //     IQ(vecs.tvPwrCorr, Option(vecs.tvPwrCorrOut)))
  //   FixedPacketDetectTester(corrParams, trials) should be (true)
  // }

//  behavior of "RealPacketDetect"
//
//  val realNoCorrParams = new PacketDetectParams[DspReal] {
//    val protoIQ = DspComplex(DspReal())
//    val powerThreshVal: Double = 0.75 // Power threshold
//    val powerThreshWindow: Int = 4 // Number of samples greater than power in a row before triggering
//    val correlationThresh: Boolean = false
//    val correlationThreshVal: Double = 0.75
//    val correlationWindow: Int = 4 // Number of strided correlations to sum
//    val correlationStride: Int = 16 // Stride between correlated samples
//  }
//  it should "detect power for reals" in {
//    val trials = Seq(IQ(vecs.tvNoPkt, None),
//      IQ(vecs.tvPwrOnly, Option(vecs.tvPwrOnlyOut)),
//      IQ(vecs.tvPwrCorr, Option(vecs.tvPwrCorrOut)))
//    RealPacketDetectTester(realNoCorrParams, trials) should be (true)
//  }
//
//  val realCorrParams = new PacketDetectParams[DspReal] {
//    val protoIQ = DspComplex(DspReal())
//    val powerThreshVal: Double = 0.75 // Power threshold
//    val powerThreshWindow: Int = 4 // Number of samples greater than power in a row before triggering
//    val correlationThresh: Boolean = true
//    val correlationThreshVal: Double = 0.75
//    val correlationWindow: Int = 4 // Number of strided correlations to sum
//    val correlationStride: Int = 16 // Stride between correlated samples
//  }
//  it should "detect power and correlation for reals" in {
//    val trials = Seq(IQ(vecs.tvNoPkt, None),
//                    IQ(vecs.tvPwrOnly, None),
//                    IQ(vecs.tvPwrCorr, Option(vecs.tvPwrCorrOut)))
//    RealPacketDetectTester(realCorrParams, trials) should be (true)
//  }

}
