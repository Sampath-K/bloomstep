// Fixed public labels only; never accept a hostname or campaign supplied by a visitor.
export const attributionFields = {
  source: ['search', 'referral', 'direct', 'campaign', 'unknown'],
  referrerDomain: ['google.com', 'bing.com', 'duckduckgo.com', 'search.yahoo.com',
    'search.brave.com', 'ecosia.org', 'github.com', 'linkedin.com', 'none', 'same_origin', 'other', 'unknown'],
  campaignSource: ['newsletter', 'google', 'bing', 'github', 'linkedin', 'community', 'unknown'],
  campaignMedium: ['email', 'organic', 'social', 'referral', 'cpc', 'unknown'],
  campaignName: ['launch', 'tiny_habits', 'garden', 'unknown'],
};
export const touchNames = ['firstTouch', 'lastTouch'];
