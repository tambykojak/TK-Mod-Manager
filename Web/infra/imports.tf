import {
  to = aws_s3_bucket.site
  id = "tkmm-gg-154086025418"
}

import {
  to = aws_s3_bucket_public_access_block.site
  id = "tkmm-gg-154086025418"
}

import {
  to = aws_s3_bucket_policy.site
  id = "tkmm-gg-154086025418"
}

import {
  to = aws_cloudfront_origin_access_control.site
  id = "E1PML0G1G1BTH7"
}

import {
  to = aws_cloudfront_function.rewrite
  id = "teekay-index-rewrite"
}

import {
  to = aws_cloudfront_distribution.site
  id = "E244AWAINL1WEC"
}

import {
  to = aws_acm_certificate.site
  id = "arn:aws:acm:us-east-1:154086025418:certificate/23f4150c-9e52-48e8-b03b-33b431e294b3"
}

import {
  to = aws_acm_certificate_validation.site
  id = "arn:aws:acm:us-east-1:154086025418:certificate/23f4150c-9e52-48e8-b03b-33b431e294b3"
}

import {
  to = aws_route53_record.cert["tkmm.gg"]
  id = "Z07684061Y1614B6FDOO2__32174bbaba7b9442eaf57ccc04c99715.tkmm.gg_CNAME"
}
