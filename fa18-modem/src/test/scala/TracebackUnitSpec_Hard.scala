package modem

import org.scalatest.{FlatSpec, Matchers}

class TracebackUnitSpec_Hard extends FlatSpec with Matchers {
  behavior of "TracebackUnitSpec_Hard"

  val params = HardCoding(
    k = 1,
    n = 2,
    K = 3,
    L = 3,
    // O = 6,
    D = 4,
    H = 24,
    genPolynomial = List(7, 6), // generator polynomial
    tailBitingEn = false,
    // tailBitingScheme = 0,
    protoBitsWidth = 16,
    bitsWidth = 48,
    softDecision = true ,
    FFTPoint = 64
  )
  it should "Traceback" in {
    HardTracebackTester(params) should be (true)
  }
}
