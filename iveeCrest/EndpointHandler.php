<?php
/**
 * EndpointHandler class file.
 *
 * PHP version 5.4
 *
 * @category IveeCrest
 * @package  IveeCrestClasses
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/EndpointHandler.php
 */

namespace iveeCrest;

/**
 * EndpointHandler implements methods for handling specific endpoints. All endpoints reachable from CREST root are
 * supported, plus a few of the endpoints deeper in the tree.
 *
 * @category IveeCrest
 * @package  IveeCrestClasses
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/EndpointHandler.php
 */
class EndpointHandler
{
    //the used representations
    const ALLIANCE_COLLECTION_REPRESENTATION            = 'vnd.ccp.eve.AllianceCollection-v1+json';
    const ALLIANCE_REPRESENTATION                       = 'vnd.ccp.eve.Alliance-v1+json';
    const CONSTELLATION_REPRESENTATION                  = 'vnd.ccp.eve.Constellation-v1+json';
    const INCURSION_COLLECTION_REPRESENTATION           = 'vnd.ccp.eve.IncursionCollection-v1+json';
    const INDUSTRY_SYSTEM_COLLECTION_REPRESENTATION     = 'vnd.ccp.eve.IndustrySystemCollection-v1';
    const INDUSTRY_FACILITY_COLLECTION_REPRESENTATION   = 'vnd.ccp.eve.IndustryFacilityCollection-v1';
    const ITEM_CATEGORY_COLLECTION_REPRESENTATION       = 'vnd.ccp.eve.ItemCategoryCollection-v1+json';
    const ITEM_CATEGORY_REPRESENTATION                  = 'vnd.ccp.eve.ItemCategory-v1+json';
    const ITEM_GROUP_COLLECTION_REPRESENTATION          = 'vnd.ccp.eve.ItemGroupCollection-v1+json';
    const ITEM_GROUP_REPRESENTATION                     = 'vnd.ccp.eve.ItemGroup-v1+json';
    const ITEM_TYPE_COLLECTION_REPRESENTATION           = 'vnd.ccp.eve.ItemTypeCollection-v1';
    const ITEM_TYPE_REPRESENTATION                      = 'vnd.ccp.eve.ItemType-v2+json';
    const KILLMAIL_REPRESENTATION                       = 'vnd.ccp.eve.Killmail-v1+json';
    const MARKET_GROUP_COLLECTION_REPRESENTATION        = 'vnd.ccp.eve.MarketGroupCollection-v1+json';
    const MARKET_GROUP_REPRESENTATION                   = 'vnd.ccp.eve.MarketGroup-v1+json';
    const MARKET_ORDER_COLLECTION_REPRESENTATION        = 'vnd.ccp.eve.MarketOrderCollection-v1+json';
    const MARKET_TYPE_COLECTION_REPRESENTATION          = 'vnd.ccp.eve.MarketTypeCollection-v1+json';
    const MARKET_TYPE_HISTORY_COLLECTION_REPRESENTATION = 'vnd.ccp.eve.MarketTypeHistoryCollection-v1+json';
    const MARKET_TYPE_PRICE_COLLECTION_REPRESENTATION   = 'vnd.ccp.eve.MarketTypePriceCollection-v1';
    const PLANET_REPRESENTATION                         = 'vnd.ccp.eve.Planet-v1+json';
    const REGION_COLLECTION_REPRESENTATION              = 'vnd.ccp.eve.RegionCollection-v1+json';
    const REGION_REPRESENTATION                         = 'vnd.ccp.eve.Region-v1+json';
    const SYSTEM_REPRESENTATION                         = 'vnd.ccp.eve.System-v1+json';
    const TOKEN_DECODE_REPRESENTATION                   = 'vnd.ccp.eve.TokenDecode-v1+json';
    const TOURNAMENT_COLLECTION_REPRESENTATION          = 'vnd.ccp.eve.TournamentCollection-v1+json';
    const WARS_COLLECTION_REPRESENTATION                = 'vnd.ccp.eve.WarsCollection-v1+json';
    const WAR_REPRESENTATION                            = 'vnd.ccp.eve.War-v1+json';

    /**
     * @var \iveeCrest\Client $client for CREST
     */
    protected $client;

    /**
     * Constructs an EndpointHandler.
     *
     * @param \iveeCrest\Client $client to be used
     *
     * @return \iveeCrest\EndpointHandler
     */
    public function __construct(Client $client)
    {
        $this->client = $client;
    }

    /**
     * Sets another Client to EndpointHandler.
     *
     * @param \iveeCrest\Client $client to be used
     *
     * @return void
     */
    public function setClient(Client $client)
    {
        $this->client = $client;
    }

    /**
     * Parses a trailing ID from a given URL. This is useful to index data returned from CREST which doesn't contain the
     * ID of the object it refers to, but provides a href which contains it.
     *
     * @param string $url to be parsed
     *
     * @return int
     */
    public static function parseTrailingIdFromUrl($url)
    {
        $trimmed = rtrim($url, '/');
        return (int) substr($trimmed, strrpos($trimmed, '/') + 1);
    }

    
    /**
     * Verifies the access token, returning data about the character linked to it.
     *
     * @return \stdClass
     */
    public function verifyAccessToken()
    {
        return $this->client->getEndpoint(
            //no path to the verify endpoint is exposed, so we need construct it
            str_replace('token', 'verify', $this->client->getRootEndpoint()->authEndpoint->href),
            true
        );
    }

    /**
     * "decodes" the access token, returning a href to the character endpoint.
     *
     * @return \stdClass
     */
    public function tokenDecode()
    {
        return $this->client->getEndpoint(
            $this->client->getRootEndpoint()->decode->href,
            true,
            static::TOKEN_DECODE_REPRESENTATION
        );
    }

    /**
     * Gathers the marketTypes endpoint.
     *
     * @return array
     */
    public function getMarketTypes()
    {
        //echo time2s()."eh.getMarketTypes()\n";
        return $this->client->gatherCached(
            $this->client->getRootEndpoint()->marketTypes->href,
            function ($marketType) {
                return (int) $marketType->type->id;
            },
            null,
            static::MARKET_TYPE_COLECTION_REPRESENTATION
        );
    }

    /**
     * Gathers the market types hrefs.
     *
     * @return array in the form typeID => href
     */
    public function getMarketTypeHrefs()
    {
        //echo time2s()."eh.getMarketTypeHrefs()\n";
        if (!isset($this->marketTypeHrefs)) {
            //gather all the pages into one compact array, indexed by item id
            $this->marketTypeHrefs = $this->client->gatherCached(
                $this->client->getRootEndpoint()->marketTypes->href,
                function ($marketType) {
                    return (int) $marketType->type->id;
                },
                function ($marketType) {
                    return $marketType->type->href;
                },
                static::MARKET_TYPE_COLECTION_REPRESENTATION,
                86400,
                'hrefsOnly'
            );
        }
        return $this->marketTypeHrefs;
    }

    /**
     * Gathers the regions endpoint.
     *
     * @return array
     */
    public function getRegions()
    {
       //echo time2s()."eh.getRegions()\n";
       return $this->client->gatherCached(
            $this->client->getRootEndpoint()->regions->href,
            function ($region) {
                return static::parseTrailingIdFromUrl($region->href);
            },
            null,
            static::REGION_COLLECTION_REPRESENTATION
        );
    }

    /**
     * Gets the endpoint for a region.
     *
     * @param int $regionId of the region
     *
     * @return \stdClass
     */
    public function getRegion($regionId)
    {
        $regions = $this->getRegions();
        if (!isset($regions[$regionId])) {
            $invalidArgumentExceptionClass = Config::getIveeClassName('InvalidArgumentException');
            throw new $invalidArgumentExceptionClass('RegionID=' . (int) $regionId . ' not found in regions');
        }

        return $this->client->getEndpoint(
            $regions[$regionId]->href,
            true,
            static::REGION_REPRESENTATION
        );
    }

    /**
     * Returns an array with all constellation hrefs. Note that this method will cause a CREST call for every region if
     * not already cached.
     *
     * @return array in the form constellationId => href
     */
    public function getConstellationHrefs()
    {
        $dataKey = 'gathered:constellationHrefs';
        try {
            $dataObj = $this->client->getCache()->getItem($dataKey);
        } catch (Exceptions\KeyNotFoundInCacheException $e){
            //get region hrefs
            $hrefs = array();
            foreach ($this->getRegions() as $region)
                $hrefs[] = $region->href;

            //instantiate Response object
            $cacheableArrayClass = Config::getIveeClassName('CacheableArray');
            $dataObj = new $cacheableArrayClass($dataKey, 24 * 3600);

            //run the async queries
            $this->client->asyncGetMultiEndpointResponses(
                $hrefs,
                function (Response $res) use ($dataObj) {
                    foreach ($res->content->constellations as $constellation)
                        $dataObj->data[EndpointHandler::parseTrailingIdFromUrl($constellation->href)]
                            = $constellation->href;
                },
                null,
                static::REGION_REPRESENTATION
            );
            $this->client->getCache()->setItem($dataObj);
        }
        return $dataObj->data;
    }

    /**
     * Gets the endpoint for a constellation.
     *
     * @param int $constellationId of the constellation
     *
     * @return \stdClass
     */
    public function getConstellation($constellationId)
    {
        $constellations = $this->getConstellationHrefs();
        if (!isset($constellations[$constellationId])) {
            $invalidArgumentExceptionClass = Config::getIveeClassName('InvalidArgumentException');
            throw new $invalidArgumentExceptionClass(
                'ConstellationID=' . (int) $constellationId . ' not found in constellations'
            );
        }

        return $this->client->getEndpoint(
            $constellations[$constellationId],
            true,
            static::CONSTELLATION_REPRESENTATION
        );
    }

    /**
     * Returns an array with all solar system hrefs. When response time is critical, using this call is not recommended
     * due to it causing over 1100 calls to CREST when not already cached.
     *
     * @return array in the form solarSystemId => href
     */
    public function getSolarSystemHrefs()
    {
        $dataKey = 'gathered:solarSystemHrefs';
        try {
            $dataObj = $this->client->getCache()->getItem($dataKey);
        } catch (Exceptions\KeyNotFoundInCacheException $e) {
            //instantiate data object
            $cacheableArrayClass = Config::getIveeClassName('CacheableArray');
            $dataObj = new $cacheableArrayClass($dataKey, 24 * 3600);

            //run the async queries
            $this->client->asyncGetMultiEndpointResponses(
                $this->getConstellationHrefs(),
                function (Response $res) use ($dataObj) {
                    foreach ($res->content->systems as $system)
                        $dataObj->data[EndpointHandler::parseTrailingIdFromUrl($system->href)] = $system->href;
                },
                null,
                static::CONSTELLATION_REPRESENTATION
            );
            $this->client->getCache()->setItem($dataObj);
        }
        return $dataObj->data;
    }

    /**
     * Gets the endpoint for a solar system.
     *
     * @param int $systemId of the solar system
     *
     * @return \stdClass
     */
    public function getSolarSystem($systemId)
    {
        return $this->client->getEndpoint(
            //Here we intentionally disregard CREST principles by constructing the URL as the official alternative is 
            //impracticable by virtue of requiring over a thousand calls to the constellation endpoint
            $this->client->getRootEndpointUrl() . '/solarsystems/' . (int) $systemId . '/',
            true,
            static::SYSTEM_REPRESENTATION
        );
    }

    /**
     * Gets buy and sell orders for a type in a region.
     *
     * @param int $typeId of the item type
     * @param int $regionId of the region
     *
     * @return \stdClass
     */
    public function getMarketOrders($typeId, $regionId)
    {
        //echo time2s()."eh.getMarketOrders()\n";
        $region = $this->getRegion($regionId);
        $marketTypeHrefs = $this->getMarketTypeHrefs();
        if (!isset($marketTypeHrefs[$typeId])) {
            $invalidArgumentExceptionClass = Config::getIveeClassName('InvalidArgumentException');
            throw new $invalidArgumentExceptionClass('TypeID=' . (int) $typeId . ' not found in market types');
        }

        $ret = new \stdClass();
        $ret->sellOrders = $this->client->gather(
            $region->marketSellOrders->href . '?type=' . $marketTypeHrefs[$typeId],
            null,
            null,
            static::MARKET_ORDER_COLLECTION_REPRESENTATION
        );
        $ret->buyOrders = $this->client->gather(
            $region->marketBuyOrders->href . '?type=' . $marketTypeHrefs[$typeId],
            null,
            null,
            static::MARKET_ORDER_COLLECTION_REPRESENTATION
        );

        return $ret;
    }
    public function getMarketSellOrders($typeId, $regionId)
    {
        //echo time2s()."eh.getMarketOrders()\n";
        $region = $this->getRegion($regionId);
        $marketTypeHrefs = $this->getMarketTypeHrefs();
        if (!isset($marketTypeHrefs[$typeId])) {
            $invalidArgumentExceptionClass = Config::getIveeClassName('InvalidArgumentException');
            throw new $invalidArgumentExceptionClass('TypeID=' . (int) $typeId . ' not found in market types');
        }

        $ret = new \stdClass();
        $ret->sellOrders = $this->client->gather(
            $region->marketSellOrders->href . '?type=' . $marketTypeHrefs[$typeId],
            null,
            null,
            static::MARKET_ORDER_COLLECTION_REPRESENTATION
        );

        return $ret;
    }
    public function getMarketBuyOrders($typeId, $regionId)
    {
        //echo time2s()."eh.getMarketOrders()\n";
        $region = $this->getRegion($regionId);
        $marketTypeHrefs = $this->getMarketTypeHrefs();
        if (!isset($marketTypeHrefs[$typeId])) {
            $invalidArgumentExceptionClass = Config::getIveeClassName('InvalidArgumentException');
            throw new $invalidArgumentExceptionClass('TypeID=' . (int) $typeId . ' not found in market types');
        }

        $ret = new \stdClass();
        $ret->buyOrders = $this->client->gather(
            $region->marketBuyOrders->href . '?type=' . $marketTypeHrefs[$typeId],
            null,
            null,
            static::MARKET_ORDER_COLLECTION_REPRESENTATION
        );

        return $ret;
    }

    /**
     * Gets market orders for multiple types in a region asynchronously. If the data for each type/region is requested
     * less frequently than the 5 minute TTL, it is advisable to disable caching via argument. Otherwise it will cause
     * unnecessary cache trashing.
     *
     * @param array $typeIds of the item types to be queried
     * @param int $regionId of the region to be queried
     * @param callable $callback a function expecting one \iveeCrest\Response object as argument, called for every
     * successful response
     * @param callable $errCallback a function expecting one \iveeCrest\Response object as argument, called for every
     * non-successful response
     * @param bool $cache if the multi queries should be cached
     *
     * @return void
     */
    public function getMultiMarketOrders(array $typeIds, $regionId, callable $callback, callable $errCallback = null,
        $cache = true
    ) {
        //echo time2s()."eh.getMultiMarketOrders()\n";
        //check for wormhole regions
        if ($regionId > 11000000) {
            $invalidArgumentExceptionClass = Config::getIveeClassName('InvalidArgumentException');
            throw new $invalidArgumentExceptionClass("Invalid regionId. Wormhole regions have no market.");
        }

        //get the necessary hrefs
        $region = $this->getRegion($regionId);
        $marketTypeHrefs = $this->getMarketTypeHrefs();
        $hrefs = array();
        foreach ($typeIds as $typeId) {
            if (!isset($marketTypeHrefs[$typeId])) {
                $invalidArgumentExceptionClass = Config::getIveeClassName('InvalidArgumentException');
                throw new $invalidArgumentExceptionClass('TypeID=' . (int) $typeId . ' not found in market types');
            }

            $hrefs[] = $region->marketSellOrders->href . '?type=' . $marketTypeHrefs[$typeId];
            $hrefs[] = $region->marketBuyOrders->href  . '?type=' . $marketTypeHrefs[$typeId];
        }

        //run the async queries
        $this->client->asyncGetMultiEndpointResponses(
            $hrefs,
            $callback,
            $errCallback,
            static::MARKET_ORDER_COLLECTION_REPRESENTATION,
            $cache
        );
    }

    /**
     * Gets market history for a type in a region.
     *
     * @param int $typeId of the item type
     * @param int $regionId of the region
     *
     * @return array indexed by the midnight timestamp of each day
     */
    public function getMarketHistory($typeId, $regionId)
    {
        $ts = strtotime(date('Y-m-d')) + 300;
        return $this->client->gatherCached(
            //Here we have to construct the URL because there's no navigable way to reach this data from CREST root
            $this->client->getRootEndpointUrl() . '/market/' . (int) $regionId . '/types/' . (int) $typeId
            . '/history/',
            function ($history) {
                return strtotime($history->date);
            },
            null,
            static::MARKET_TYPE_HISTORY_COLLECTION_REPRESENTATION,
            time() < $ts ? $ts : $ts + 24 * 3600 //time cache TTL to 5 minutes past midnight
        );
    }

    /**
     * Gets market history for multiple types in a region asynchronously. If the market history for each type/region
     * is only called once per day (for instance when persisted in a DB), it is advisable to disable caching via
     * argument. Otherwise it can quickly overflow the cache.
     *
     * @param array $typeIds of the item types
     * @param int $regionId of the region
     * @param callable $callback a function expecting one \iveeCrest\Response object as argument, called for every
     * successful response
     * @param callable $errCallback a function expecting one \iveeCrest\Response object as argument, called for every
     * non-successful response
     * @param bool $cache if the multi queries should be cached
     *
     * @return void
     */
    public function getMultiMarketHistory(array $typeIds, $regionId, callable $callback,
        callable $errCallback = null, $cache = true
    ) {
        //check for wormhole regions
        if ($regionId > 11000000) {
            $invalidArgumentExceptionClass = Config::getIveeClassName('InvalidArgumentException');
            throw new $invalidArgumentExceptionClass("Invalid regionId. Wormhole regions have no market.");
        }

        //Here we have to construct the URLs because there's no navigable way to reach this data from CREST root
        $hrefs = array();
        $rootUrl = $this->client->getRootEndpointUrl();
        foreach ($typeIds as $typeId)
            $hrefs[] = $rootUrl . '/market/' . (int) $regionId . '/types/' . (int) $typeId . '/history/';

        //run the async queries
        $this->client->asyncGetMultiEndpointResponses(
            $hrefs,
            $callback,
            $errCallback,
            static::MARKET_TYPE_HISTORY_COLLECTION_REPRESENTATION,
            $cache
        );
    }

    /**
     * Gets the endpoint for a industry systems, containing industry indices.
     *
     * @return array
     */
    public function getIndustrySystems()
    {
        return $this->client->gatherCached(
            $this->client->getRootEndpoint()->industry->systems->href,
            function ($system) {
                return (int) $system->solarSystem->id;
            },
            null,
            static::INDUSTRY_SYSTEM_COLLECTION_REPRESENTATION
        );
    }

    /**
     * Gets the endpoint for a market prices, containing average and adjusted prices.
     *
     * @return array
     */
    public function getMarketPrices()
    {
        //echo time2s()."eh.getMarketPrices()\n";
        return $this->client->gatherCached(
            $this->client->getRootEndpoint()->marketPrices->href,
            function ($price) {
                return (int) $price->type->id;
            },
            null,
            static::MARKET_TYPE_PRICE_COLLECTION_REPRESENTATION
        );
    }

    /**
     * Gets the endpoint for a industry facilities.
     *
     * @return array
     */
    public function getIndustryFacilities()
    {
        return $this->client->gatherCached(
            $this->client->getRootEndpoint()->industry->facilities->href,
            function ($facility) {
                return (int) $facility->facilityID;
            },
            null,
            static::INDUSTRY_FACILITY_COLLECTION_REPRESENTATION
        );
    }

    /**
     * Gathers the item groups endpoint.
     *
     * @return array
     */
    public function getItemGroups()
    {
        //echo time2s()."eh.getItemGroups()\n";
        return $this->client->gatherCached(
            $this->client->getRootEndpoint()->itemGroups->href,
            function ($group) {
                return static::parseTrailingIdFromUrl($group->href);
            },
            null,
            static::ITEM_GROUP_COLLECTION_REPRESENTATION
        );
    }

    /**
     * Gets the endpoint for an item group.
     *
     * @param int $groupId of the item group.
     *
     * @return \stdClass
     */
    public function getItemGroup($groupId)
    {
        $groups = $this->getItemGroups();
        if (!isset($groups[$groupId])) {
            $invalidArgumentExceptionClass = Config::getIveeClassName('InvalidArgumentException');
            throw new $invalidArgumentExceptionClass('GroupID=' . (int) $groupId . ' not found in groups');
        }

        return $this->client->getEndpoint(
            $groups[$groupId]->href,
            true,
            static::ITEM_GROUP_REPRESENTATION
        );
    }

    /**
     * Gathers the alliances endpoint.
     *
     * @return array
     */
    public function getAlliances()
    {
        return $this->client->gatherCached(
            $this->client->getRootEndpoint()->alliances->href,
            function ($alliance) {
                return (int) $alliance->href->id;
            },
            function ($alliance) {
                return $alliance->href;
            },
            static::ALLIANCE_COLLECTION_REPRESENTATION
        );
    }

    /**
     * Gets the endpoint for an alliance.
     *
     * @param int $allianceId of the alliance
     *
     * @return \stdClass
     */
    public function getAlliance($allianceId)
    {
        $alliances = $this->getAlliances();
        if (!isset($alliances[$allianceId])) {
            $invalidArgumentExceptionClass = Config::getIveeClassName('InvalidArgumentException');
            throw new $invalidArgumentExceptionClass('AllianceID=' . (int) $allianceId . ' not found in alliances');
        }
        return $this->client->getEndpoint(
            $alliances[$allianceId]->href,
            true,
            static::ALLIANCE_REPRESENTATION
        );
    }

    /**
     * Gathers the item type endpoint.
     *
     * @return array
     */
    public function getItemTypes()
    {
        //echo time2s()."eh.getItemTypes()\n";
        return $this->client->gatherCached(
            $this->client->getRootEndpoint()->itemTypes->href,
            function ($type) {
                return static::parseTrailingIdFromUrl($type->href);
            },
            null,
            static::ITEM_TYPE_COLLECTION_REPRESENTATION
        );
    }

    /**
     * Gets the endpoint for an item type.
     *
     * @param int $typeId of the type
     *
     * @return \stdClass
     */
    public function getType($typeId)
    {
        $itemTypes = $this->getItemTypes();
        if (!isset($itemTypes[$typeId])) {
            $invalidArgumentExceptionClass = Config::getIveeClassName('InvalidArgumentException');
            throw new $invalidArgumentExceptionClass('TypeID=' . (int) $typeId . ' not found in types');
        }

        return $this->client->getEndpoint(
            $itemTypes[$typeId]->href,
            true,
            static::ITEM_TYPE_REPRESENTATION
        );
    }

    /**
     * Gathers the item categories endpoint.
     *
     * @return array
     */
    public function getItemCategories()
    {
        return $this->client->gatherCached(
            $this->client->getRootEndpoint()->itemCategories->href,
            function ($category) {
                return static::parseTrailingIdFromUrl($category->href);
            },
            null,
            static::ITEM_CATEGORY_COLLECTION_REPRESENTATION
        );
    }

    /**
     * Gets the endpoint for an item category.
     *
     * @param int $categoryId of the category
     *
     * @return \stdClass
     */
    public function getItemCategory($categoryId)
    {
        $categories = $this->getItemCategories();
        if (!isset($categories[$categoryId])) {
            $invalidArgumentExceptionClass = Config::getIveeClassName('InvalidArgumentException');
            throw new $invalidArgumentExceptionClass('CategoryID=' . (int) $categoryId . ' not found in categories');
        }

        return $this->client->getEndpoint(
            $categories[$categoryId]->href,
            true,
            static::ITEM_CATEGORY_REPRESENTATION
        );
    }

    /**
     * Gathers the item market groups endpoint.
     *
     * @return array
     */
    public function getMarketGroups()
    {
        //echo time2s()."eh.getMarketGroups()\n";
        return $this->client->gatherCached(
            $this->client->getRootEndpoint()->marketGroups->href,
            function ($group) {
                return static::parseTrailingIdFromUrl($group->href);
            },
            null,
            static::MARKET_GROUP_COLLECTION_REPRESENTATION
        );
    }

    /**
     * Gets the endpoint for a market group.
     *
     * @param int $marketGroupId of the market group
     *
     * @return \stdClass
     */
    public function getMarketGroup($marketGroupId)
    {
        //echo time2s()."eh.getMarketGroup()\n";
        $marketGroups = $this->getMarketGroups();
        if (!isset($marketGroups[$marketGroupId])) {
            $invalidArgumentExceptionClass = Config::getIveeClassName('InvalidArgumentException');
            throw new $invalidArgumentExceptionClass(
                'MarketGroupId=' . (int) $marketGroupId . ' not found in market groups'
            );
        }

        return $this->client->getEndpoint(
            $marketGroups[$marketGroupId]->href,
            true,
            static::MARKET_GROUP_REPRESENTATION
        );
    }

    /**
     * Gets the types for a market group.
     *
     * @param int $marketGroupId of the market group
     *
     * @return array
     */
    public function getMarketGroupTypes($marketGroupId)
    {
        //echo time2s()."eh.getMarketGroupTypes()\n";
        return $this->client->gatherCached(
            $this->getMarketGroup($marketGroupId)->types->href,
            function ($type) {
                return (int) $type->type->id;
            },
            null,
            static::MARKET_TYPE_COLECTION_REPRESENTATION
        );
    }

    /**
     * Gets the tournaments endpoint.
     *
     * @return array
     */
    public function getTournaments()
    {
        return $this->client->gatherCached(
            $this->client->getRootEndpoint()->tournaments->href,
            function ($tournament) {
                return static::parseTrailingIdFromUrl($tournament->href->href);
            },
            function ($tournament) {
                return $tournament->href;
            },
            static::TOURNAMENT_COLLECTION_REPRESENTATION
        );
    }

    /**
     * Returns all wars. Using this method is not recommended. The number of wars is in the hundreds of thousands, and
     * the result exceeds the default maximum cacheable data size of memcached, which is 1MB. If you must use it,
     * consider increasing memcached max item size to 4MB by setting the option "-I 4m" in its configuration.
     *
     * @return array in the form ID => href
     */
    public function getWarHrefs()
    {
        return $this->client->gatherCached(
            $this->client->getRootEndpoint()->wars->href,
            function ($war) {
                return (int) $war->id;
            },
            function ($war) {
                return $war->href;
            },
            static::WARS_COLLECTION_REPRESENTATION
        );
    }

    /**
     * Gets the endpoint for a war.
     *
     * @param int $warId of the war
     *
     * @return \stdClass
     */
    public function getWar($warId)
    {
        //we don't use the wars collection here due to it's huge size
        return $this->client->getEndpoint(
            $this->client->getRootEndpoint()->wars->href . (int) $warId . '/',
            true,
            static::WAR_REPRESENTATION
        );
    }

    /**
     * Gets the incursions endpoint.
     *
     * @return array
     */
    public function getIncursions()
    {
        return $this->client->getEndpoint(
            $this->client->getRootEndpoint()->incursions->href,
            true,
            static::INCURSION_COLLECTION_REPRESENTATION
        );
    }

    /**
     * Gets a Killmail. The domain of the passed href is adapted to the currently used CREST root, so all hrefs in the
     * response are relative to that.
     *
     * @param string $killmailHref in the form 
     * http://public-crest.eveonline.com/killmails/30290604/787fb3714062f1700560d4a83ce32c67640b1797/
     *
     * @return \stdClass
     */
    public function getKillmail($killmailHref)
    {
        return $this->client->getEndpoint(
            $this->client->getRootEndpointUrl() . ltrim(parse_url($killmailHref, PHP_URL_PATH), '/'),
            true,
            static::KILLMAIL_REPRESENTATION
        );
    }
}
