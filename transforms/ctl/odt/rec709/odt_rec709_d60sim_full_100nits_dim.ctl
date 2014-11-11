// 
// Output Device Transform to Rec709
// WGR8.5
//

//
// Summary :
//  This transform is intended for mapping OCES onto a Rec.709 broadcast monitor
//  that is calibrated to a D65 white point at 100 cd/m^2. The assumed observer 
//  adapted white is D65, and the viewing environment is dim. 
//
// Device Primaries : 
//  Primaries are those specified in Rec. ITU-R BT.709
//  CIE 1931 chromaticities:  x         y         Y
//              Red:          0.64      0.33
//              Green:        0.3       0.6
//              Blue:         0.15      0.06
//              White:        0.3217    0.329     100 cd/m^2
//
// Display EOTF :
//  The reference electro-optical transfer function specified in 
//  Rec. ITU-R BT.1886.
//
// Assumed observer adapted white point:
//         CIE 1931 chromaticities:    x            y
//                                     0.3217       0.329
//
// Viewing Environment:
//     This ODT makes an attempt to compensate for viewing environment variables //     more typical of those associated with the home.
//



import "utilities";
import "transforms-common";
import "odt-transforms-common";



/* --- ODT Parameters --- */
const Chromaticities DISPLAY_PRI = REC709_PRI;
// const float OCES_PRI_2_XYZ_MAT[4][4] = RGBtoXYZ(ACES_PRI,1.0);
const float XYZ_2_DISPLAY_PRI_MAT[4][4] = XYZtoRGB(DISPLAY_PRI,1.0);

const float DISPGAMMA = 2.4; 
const float L_W = 1.0;
const float L_B = 0.0;

const float SCALE = 0.955;

// Gamma compensation factor (very small change) if brighter surround environment.
const float SURROUNDGAMMA = 0.9811;

const float DESATFACTOR = 0.93;

const float RGB2Y[3] = { RENDER_PRI_2_XYZ_MAT[0][1], 
                         RENDER_PRI_2_XYZ_MAT[1][1], 
                         RENDER_PRI_2_XYZ_MAT[2][1] };
const float SAT_MAT[3][3] = calc_sat_adjust_matrix( DESATFACTOR, RGB2Y);

const float FLARE = 1/2500.;


void main 
(
  input varying float rIn, 
  input varying float gIn, 
  input varying float bIn, 
  input varying float aIn,
  output varying float rOut,
  output varying float gOut,
  output varying float bOut,
  output varying float aOut
)
{
  // --- Initialize a 3-element vector with input variables (OCES) --- //
    float oces[3] = { rIn, gIn, bIn};

  // --- Apply the tonescale independently in rendering-space RGB --- //
    // OCES to RGB rendering space
    float rgbPre[3] = mult_f3_f44( oces, ACES_2_RENDER_PRI_MAT);

    // Tonescale
    float rgbPost[3];
    rgbPost[0] = odt_tonescale_segmented_fwd( rgbPre[0]);
    rgbPost[1] = odt_tonescale_segmented_fwd( rgbPre[1]);
    rgbPost[2] = odt_tonescale_segmented_fwd( rgbPre[2]);

  // --- Scale luminance to black and white normalized code values --- //
    float linearCV[3];
    linearCV[0] = Y_2_linCV( rgbPost[0], 48.0, 0.0048);
    linearCV[1] = Y_2_linCV( rgbPost[1], 48.0, 0.0048);
    linearCV[2] = Y_2_linCV( rgbPost[2], 48.0, 0.0048);

  // --- Compensate for different white point being darker  --- //
  // This adjustment is to correct an issue that exists in ODTs where the device 
  // is calibrated to a white chromaticity other than D60. In order to simulate 
  // D60 on such devices, unequal code values are sent to the display to achieve 
  // neutrals at D60. In order to produce D60 on a device calibrated to the DCI 
  // white point (i.e. equal code values yield CIE x,y chromaticities of 0.314, 
  // 0.351) the red channel is higher than green and blue to compensate for the 
  // "greenish" DCI white. This is the correct behavior but it means that as 
  // highlight increase, the red channel will hit the device maximum first and 
  // clip, resulting in a chromaticity shift as the green and blue channels 
  // continue to increase.
  // To avoid this clipping error, a slight scale factor is applied to allow the 
  // ODTs to simulate D60 within the D65 calibration white point. 

    // Scale and clamp white to avoid casted highlights due to D60 simulation
    linearCV[0] = min( linearCV[0], 1.0) * SCALE;
    linearCV[1] = min( linearCV[1], 1.0) * SCALE;
    linearCV[2] = min( linearCV[2], 1.0) * SCALE;

  // --- Apply gamma adjustment to compensate for surround --- //
    float XYZ[3] = mult_f3_f44( linearCV, RENDER_PRI_2_XYZ_MAT); 

    float xyY[3] = XYZ_2_xyY(XYZ);
    xyY[2] = pow( xyY[2], SURROUNDGAMMA);
    XYZ = xyY_2_XYZ(xyY);

  // --- Apply desaturation --- //
    linearCV = mult_f3_f44( XYZ, XYZ_2_RENDER_PRI_MAT); // XYZ to RGB
    
    linearCV = mult_f3_f33( linearCV, SAT_MAT);
    
    XYZ = mult_f3_f44( linearCV, RENDER_PRI_2_XYZ_MAT);

  // --- Convert to display primaries --- //
    linearCV = mult_f3_f44( XYZ, XYZ_2_DISPLAY_PRI_MAT);

  // --- Handle out-of-gamut values --- //
    // Clip values < 0 or > 1 (i.e. projecting outside the display primaries)
    linearCV = clamp_f3( linearCV, 0., 1.);

  // --- Add flare for dynamic range matching to projector --- //
    linearCV = add_f_f3( FLARE, linearCV);

  // --- Encode linear code values with transfer function --- //
    float outputCV[3];
    outputCV[0] = bt1886_r( linearCV[0], DISPGAMMA, L_W, L_B);
    outputCV[1] = bt1886_r( linearCV[1], DISPGAMMA, L_W, L_B);
    outputCV[2] = bt1886_r( linearCV[2], DISPGAMMA, L_W, L_B);
  
  // --- Cast outputCV to rOut, gOut, bOut --- //
    rOut = outputCV[0];
    gOut = outputCV[1];
    bOut = outputCV[2];
    aOut = aIn;
}