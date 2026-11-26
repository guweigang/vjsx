import { rootValue } from "vjsx-conformance-pkg";
import { featureValue } from "vjsx-conformance-pkg/feature";
import { featureValue as viaPattern } from "vjsx-conformance-pkg/nested/feature";
import { featureValue as viaSpecificPattern } from "vjsx-conformance-pkg/nested/deep/feature.js";
import { rootValue as viaExact } from "vjsx-conformance-pkg/nested/deep/root.js";

export const packageResult =
  viaPattern === featureValue && viaSpecificPattern === featureValue && viaExact === rootValue
    ? rootValue + featureValue
    : 0;
