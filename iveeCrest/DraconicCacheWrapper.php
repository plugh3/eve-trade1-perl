<?php
/**
 * MemcachedWrapper class file.
 *
 * PHP version 5.4
 *
 * @category IveeCrest
 * @package  IveeCrestClasses
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/MemcachedWrapper.php
 */

namespace iveeCrest;

/**
 * MemcachedWrapper provides caching functionality for iveeCrest based on php5-memcached.
 *
 * Pulling data from CREST is a relative expensive process thats slows down the client application and puts load onto
 * CCP's infrastructure. CCP thus asks developers to implement client side caching mechanisms, respecting the cache
 * times specified in the response header as much as possible.
 *
 * @category IveeCrest
 * @package  IveeCrestClasses
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/MemcachedWrapper.php
 */
class DraconicCacheWrapper implements ICache
{
    /**
     * @var \Memcached $memcached holds the Memcached connections.
     */
    protected $cache2;

    /**
     * @var int $hits stores the number of hits on memcached.
     */
    protected $hits = 0;

    /**
     * @var string $uniqId to be used to separate objects in addition to their key identifiers, for instance in a
     * multi-user scenario.
     */
    protected $uniqId;

    /**
     * Constructor
     *
     * @param string $uniqId to be used to separate objects in addition to their key identifiers, for instance in a
     * multi-user scenario.
     *
     * @return \iveeCrest\MemcachedWrapper
     */
    public function __construct($uniqId)
    {
        //echo "cache.new()\n";
        $this->cache2 = array();
        $this->uniqId = $uniqId;
    }

    /**
     * Stores item in Memcached.
     *
     * @param ICacheable $item to be stored
     *
     * @return boolean true on success
     */
    public function setItem(ICacheable $item)
    {
        $key = $item->getKey();
        //$ckey = md5($this->uniqId . '_' . $key);
        $ckey = $key;
        $ttl1 = $item->getCacheTTL(); // ivee TTL
        $ttl2 = time() + $item->getCacheTTL() - 10;

        //echo "cache.setItem() TTL=$ttl1 $key\n";
        //print_r($item);

        //if (strpos($key, "oauth/token") !== false) { $ttl2 = time() + 30; }

        $citem = array(
            'key'   => $key,
            'value' => $item,
            'expire'=> $ttl2    // NOTUSED?
        );
        
        $this->cache2[$ckey] = $citem;
        return 1;
    }

    /**
     * Gets item from Memcached.
     *
     * @param string $key under which the item is stored
     *
     * @return mixed
     * @throws \iveeCrest\Exceptions\KeyNotFoundInCacheException if key is not found
     */
    public function getItem($key)
    {
        //$ckey = md5($this->uniqId . '_' . $key);
        $ckey = $key;
        
        if (empty($this->cache2[$ckey])) {
            $exceptionClass = Config::getIveeClassName('KeyNotFoundInCacheException');
            throw new $exceptionClass("Key not found in cache.");
        }
        $citem = $this->cache2[$ckey];
        $item = $citem['value'];
        $ttl = $item->getCacheTTL();
        $expire = $citem['expire'];
        
        if (strpos($key, "oauth/token") !== false) {
            echo time2s()."getItem() token cache_TTL $ttl\n";
        }
        if (strpos($key, "orders/sell") !== false) {
            //echo time2s()."getItem() order cache_TTL $ttl\n";
        }
        
        // TODO: do we need to throw an exception on TTL expiration?
        //$this->cache2[$ckey]['value']->getCacheTTL();
        
        if (time() >= $expire) {
            $exceptionClass = Config::getIveeClassName('KeyNotFoundInCacheException');
            throw new $exceptionClass("Key not found in cache.");
            echo time2s.">>> cache item expired $key\n";
        }
        
        
        //count cache hit
        $this->hits++;
        return $item;
    }

    /**
     * Removes item from Memcached.
     *
     * @param string $key of object to be removed
     *
     * @return bool true on success or if memcached has been disabled
     */
    public function deleteItem($key)
    {
        //echo "cache.deleteItem() key=$key\n";

        //$ckey = md5($this->uniqId . '_' . $key);
        $ckey = $key;
        if (empty($this->cache2[$ckey])) { return 0; }
        unset($this->cache2[$ckey]);
        return 1;
    }

    /**
     * Removes multiple items from Memcached.
     * If using memcached, this method requires php5-memcached package version >=2.0!
     *
     * @param array $keys of items to be removed
     *
     * @return bool true on success, also if memcached has been disabled
     */
    public function deleteMulti(array $keys)
    {
        echo "cache.deleteMulti()\n";
        foreach ($keys as $key) {
            //$ckey = md5($this->uniqId . '_' . $key);
            $ckey = $key;
            unset($this->cache2[$ckey]);
        }
        return 1;
    }

    /**
     * Clears all stored items in memcached.
     *
     * @return boolean true on success, also if memcached has been disabled.
     */
    public function flushCache()
    {
        echo "cache.flushCache()\n";
        foreach ($this->cache2 as $ckey => $citem) {
            unset($this->cache2[$ckey]);
        }
        $this->cache2 = array();
        return 1;
    }

    /**
     * Gets the number of hits the cache wrapper registered.
     *
     * @return int the number of hits
     */
    public function getHits()
    {
        return $this->hits; 
    }

    
    
    //
    // draconic adds
    //
    public function exportCache($fname)
    {
        //echo time2s()."cache.exportCache() $fname\n";

        $text = serialize($this->cache2);
                
        $fh = fopen($fname, 'w') or die("Failed to open $fname");
        flock($fh, LOCK_EX);
        fwrite($fh, $text);
        flock($fh, LOCK_UN);
        fclose($fh);

        //foreach ($this->cache2 as $ckey => $citem) {
    }
    public function importCache($fname)
    {
        echo time2s()."cache.importCache() $fname\n";

        if (!file_exists($fname)) {
            echo time2s()."dc.importCache() no cache file $fname\n";
            return; 
        }
        
        $fh = fopen($fname, 'r');
        flock($fh, LOCK_EX);
        $text = fread($fh, filesize($fname));
        flock($fh, LOCK_UN);
        fclose($fh);

        $this->cache2 = unserialize($text);
    }
    public function printCache()
    {
        echo "cache.printCache()\n";
        foreach ($this->cache2 as $ckey => $citem) 
        {
            echo "   $ckey\n";
        }
    }
}
