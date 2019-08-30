package modem

import org.scalatest.{FlatSpec, Matchers}

import scala.util.Random

class BranchMetricUnitSpec2_SINT extends FlatSpec with Matchers {
  behavior of "BranchMetric2 UnitSpec"

  val params = HardCoding(
    k = 1,
    n = 2,
    K = 3,
    L = 7,
//    O = 6,
    D = 36,
    H = 24,
    genPolynomial = List(7, 5), // generator polynomial
    tailBitingEn = false,
//    tailBitingScheme = 0,
    protoBitsWidth = 16,
    bitsWidth = 48,
    softDecision = false,
    FFTPoint = 64
  )
  it should "calculate Branch Metrics2" in {
    val n = 10
    val trellisObj  = new Trellis(params)
    val outputTable = trellisObj.output_table
    val inSeq0      = Seq.fill(n)(Random.nextFloat).map(_.round).map(2 * _ - 1)
    val inSeq1      = Seq.fill(n)(Random.nextFloat).map(_.round).map(2 * _ - 1)
    val inSeq       = inSeq0.zip(inSeq1)

    val baseTrial   = BranchMetricInOut2_SINT(inBit0=0, inBit1=0, outBitSeq=outputTable)
    val trials      = inSeq.map { case(a,b) => baseTrial.copy(inBit0 = a, inBit1 = b)}

    FixedBranchMetricTester2_SINT(params, trials) should be (true)
  }
}
