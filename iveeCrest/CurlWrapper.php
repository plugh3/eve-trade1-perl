<?php
/**
 * CurlWrapper class file.
 *
 * PHP version 5.4
 *
 * @category IveeCrest
 * @package  IveeCrestClasses
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/CurlWrapper.php
 */

namespace iveeCrest;

/**
 * CurlWrapper is a CREST-specific wrapper around CURL. It handles GET, POST and OPTIONS requests. Parallel asynchronous
 * GET is also available, as well as integration with the caching mechanisms of iveeCrest.
 *
 * @category IveeCrest
 * @package  IveeCrestClasses
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/CurlWrapper.php
 */
class CurlWrapper
{
    /**
     * @var \iveeCrest\ICache $cache used to cache Response objects
     */
    protected $cache;

    /**
     * @var string $userAgent the user agent to be used
     */
    protected $userAgent;

    /**
     * @var curl_handle $ch
     */
    protected $ch;

    protected $requeued;

    /**
     * Constructor.
     * 
     * @param string $userAgent to be used in the requests to CREST.
     * @param string $refreshToken related to the user/character. Used to ensure data separation in the cache.
     *
     * @return \iveeCrest\CurlWrapper
     */
    function __construct($userAgent, $refreshToken)
    {
        $this->userAgent = $userAgent;
        $this->ch = curl_init();
        $this->requeued = array();
        
        //set standard CURL options
        curl_setopt_array(
            $this->ch,
            array(
                CURLOPT_RETURNTRANSFER  => true,
                CURLOPT_USERAGENT       => $this->userAgent,
                CURLOPT_SSL_VERIFYPEER  => true,
                CURLOPT_SSL_CIPHER_LIST => 'TLSv1', //prevent protocol negotiation fail
				CURLOPT_CAINFO          => __DIR__ . DIRECTORY_SEPARATOR . 'cacert.pem',
            )
        );

        $cacheClass = Config::getIveeClassName('Cache');
        $this->cache = new $cacheClass(get_called_class() . '_' . $refreshToken);
    }

    /**
     * Destructor. Lets cleanly close the curl handle.
     *
     * @return void
     */
    function __destruct()
    {
        curl_close($this->ch);
    }

    /**
     * Performs POST request.
     * 
     * @param string $uri the URI to make the request to
     * @param array $header to be used in http request
     * @param array $fields parameters to be passed in the request in the form param => value
     * 
     * @return \iveeCrest\Response
     * @throws \iveeCrest\Exceptions\CrestException on http return codes other than 200 and 302
     */
    public function post($uri, array $header, array $fields)
    {
        $responseKey = 'post:' . $uri;
        try {
            // if access token request, skip cache
            if (strpos($uri, 'oauth/token') !== false) { throw new \iveeCrest\Exceptions\KeyNotFoundInCacheException('new access token'); }

            $ret = $this->cache->getItem($responseKey);
            echo time2s()."cw.post(cache) $uri\n";
            return $ret;
        } catch (Exceptions\KeyNotFoundInCacheException $e) {
            //url-ify the data for the POST
            $fields_string = '';
            foreach ($fields as $key => $value)
                $fields_string .= $key . '=' . $value . '&';
            rtrim($fields_string, '&');

            $responseClass = Config::getIveeClassName('Response');
            $response = new $responseClass($responseKey);
            //the curl options
            $curlOptions = array(
                CURLOPT_URL             => $uri,
                CURLOPT_POST            => true,
                CURLOPT_POSTFIELDS      => $fields_string,
                CURLOPT_HTTPHEADER      => $header,
                CURLOPT_HEADERFUNCTION  => array($response, 'handleCurlHeaderLine')
            );
            echo time2s()."cw.post ".str_replace(Config::getCrestBaseUrl(), "", $uri)."\n";
            if (strpos($uri, 'oauth/token') !== false) { 
                //var_dump($header);
                //var_dump($fields);
            }
            $this->doRequest($curlOptions, $response);
            return $response;
        }
    }

    /**
     * Performs GET request.
     * 
     * @param string $uri the URI to make the request to
     * @param string $header header to be passed in the request
     * 
     * @return \iveeCrest\Response
     * @throws \iveeCrest\Exceptions\CrestException on http return codes other than 200 and 302
     */
    public function get($uri, array $header) 
    {
        $responseKey = 'get:' . $uri;
        try {
            $ret = $this->cache->getItem($responseKey);

            /*
            // skip cache for market orders
            if (strpos($uri, "/orders/sell/") !== false OR 
                strpos($uri, "/orders/buy/")  !== false) 
            {
                throw new \iveeCrest\Exceptions\KeyNotFoundInCacheException("market order $uri");
            }
            */
            
            //$ttl1 = $ret->getCacheTTL();
            //if (true || strpos($uri, "/regions/") === false)
            //    echo time2s()."cw.get(cache)  TTL=".($ttl1)." $uri\n";
            return $ret;
        } catch (Exceptions\KeyNotFoundInCacheException $e) {
            $responseClass = Config::getIveeClassName('Response');
            $response = new $responseClass($responseKey);
            //the curl options
            $curlOptions = array(
                CURLOPT_URL             => $uri,
                CURLOPT_HTTPGET         => true, //reset to GET if we used other verb earlier
                CURLOPT_HTTPHEADER      => $header,
                CURLOPT_HEADERFUNCTION  => array($response, 'handleCurlHeaderLine')
            );
            echo time2s()."cw.get "."/".substr($uri, strlen(Config::getCrestBaseUrl()))."\n";
            $this->doRequest($curlOptions, $response);
            return $response;
        }
    }

    /**
     * Performs OPTIONS request.
     * 
     * @param string $uri the URI to make the request to
     * 
     * @return \iveeCrest\Response
     * @throws \iveeCrest\Exceptions\CrestException on http return codes other than 200 and 302
     */
    public function options($uri)
    {
        $responseKey = 'options:' . $uri;
        try {
            return $this->cache->getItem($responseKey);
        } catch (Exceptions\KeyNotFoundInCacheException $e) {
            $responseClass = Config::getIveeClassName('Response');
            $response = new $responseClass($responseKey);
            //set all the curl options
            $curlOptions = array(
                CURLOPT_URL             => $uri,
                CURLOPT_CUSTOMREQUEST   => 'OPTIONS',
                CURLOPT_HEADERFUNCTION  => array($response, 'handleCurlHeaderLine')
            );
            $this->doRequest($curlOptions, $response);
            return $response;
        }
    }

    /**
     * Performs generic request.
     *
     * @param array $curlOptArray the options array for CURL
     * @param \iveeCrest\Response $response object
     *
     * @return void
     * @throws \iveeCrest\Exceptions\CrestException on http return codes other than 200 and 302
     */
    protected function doRequest(array $curlOptArray, Response $response)
    {
        //set the curl options
        curl_setopt_array($this->ch, $curlOptArray);
        
        //execute request
        $resBody = curl_exec($this->ch);
        $info    = curl_getinfo($this->ch);
        $err     = curl_errno($this->ch);
        $errmsg  = curl_error($this->ch);

        if ($err != 0) {
            $crestExceptionClass = Config::getIveeClassName('CrestException');
            throw new $crestExceptionClass($errmsg, $err);
        }
            
        if (!in_array($info['http_code'], array(200, 302))) {
            $crestExceptionClass = Config::getIveeClassName('CrestException');
            throw new $crestExceptionClass(
                'HTTP response not OK: ' . (int)$info['http_code'] . '. Response body: ' . $resBody,
                $info['http_code']
            );
        }

        //set data to response and cache it
        $response->setInfo($info);
        $response->setContent($resBody);
        $this->cache->setItem($response);
    }

	public function backspace($x = 1)
	{
		$ret = "";
		for ($i = 0; $i < $x; $i++) { $ret .= "\x8"; }
		return $ret;
	}
		
	// calculates rate of events over fixed period
	public $currRate = 0.0;
	public $max_rate = 0.0;
	protected $countsByTime = array();
	protected $n_gets = 0;
	protected function recordEvent()
	{
		$samplePeriod = 0.5;  ## sample period used to calculate instantaneous rate

		### event counter + current time
		$now = microtime(true);
		$this->n_gets++;

		### add to history
		array_unshift($this->countsByTime, array($this->n_gets, $now));

		### find far side of sample window
		$n_sample = 0;
		$t_sample = $now;
		for ($i_sample = 0; $i_sample < count($this->countsByTime); $i_sample++) {
			list ($n_sample, $t_sample) = $this->countsByTime[$i_sample];
			if ($now - $t_sample >= $samplePeriod) { break; }
		}

		### calculate rate (n/usec)
		$rate = ($now != $t_sample) 
			? (($this->n_gets - $n_sample) / ($now - $t_sample))
			: (0.0);
		$this->currRate = $rate;
		if ($rate > $this->max_rate) { $this->max_rate = $rate; }
		
		### output current rate
		$out = sprintf("%7.1f", $rate)." GET/s"; ## gets/sec
		echo($this->backspace(strlen($out)));
		echo $out;
	}
	
    /**
     * Performs parallel asynchronous GET requests.
     * 
     * @param array $hrefs the hrefs to request
     * @param array $header the header to be passed in all requests
     * @param callable $getAuthHeader that returns an appropriate bearer authentication header line, for instance 
     * Client::getBearerAuthHeader(). We do this on-the-fly as during large multi GET batches the access token might
     * expire.
     * @param callable $callback a function expecting one \iveeCrest\Response object as argument, called for every
     * successful response
     * @param callable $errCallback a function expecting one \iveeCrest\Response object as argument, called for every
     * non-successful response
     * @param bool $cache whether the Responses should be cached
     * 
     * @return void
     * @throws \iveeCrest\Exceptions\IveeCrestException on general CURL error
     */
    public function asyncMultiGet(array $hrefs, array $header, callable $getAuthHeader, callable $callback,
        callable $errCallback = null, $cache = true
    ) {
		$maxWindow = 100;

        echo time2s()."curl.asyncMultiGet(".sprintf("%4d", count($hrefs)).") x$maxWindow => ".sprintf("%7.1f", 0.0)." GET/s"; 
		//var_dump($hrefs);

        //separate hrefs that are already cached from those that need to be requested
        $hrefsToQuery = array();
        foreach ($hrefs as $href) {
            $responseKey = 'get:' . $href;
            try {
                $callback($this->cache->getItem($responseKey));
            } catch (Exceptions\KeyNotFoundInCacheException $e){
                $hrefsToQuery[] = $href;
            }
            if (! in_array($href, $hrefsToQuery)) { // $hrefsToQuery: not in cache
                $url_short = str_replace(Config::getCrestBaseUrl(), '', $href);
                echo time2s()."cache ".$url_short."\n";
            }
        }

        // make sure the rolling window isn't greater than the number of hrefs
        $rollingWindow = count($hrefsToQuery) > $maxWindow ? $maxWindow : count($hrefsToQuery);

        //CURL options for all requests
        $stdOptions = array(
            CURLOPT_RETURNTRANSFER  => true,
            CURLOPT_USERAGENT       => $this->userAgent,
            CURLOPT_SSL_VERIFYPEER  => true,
            CURLOPT_SSL_CIPHER_LIST => 'TLSv1', //prevent protocol negotiation fail
            CURLOPT_CAINFO          => __DIR__ . DIRECTORY_SEPARATOR . 'cacert.pem',
            CURLOPT_HTTPHEADER      => $header
        );

        $responses = array();
        $master = curl_multi_init();
        //setup the first batch of requests
        for ($i = 0; $i < $rollingWindow; $i++) {
            $href = $hrefsToQuery[$i];
            #echo time2s()."curl.multi  $href\n";
            $responses[$href] = $this->addHandleToMulti($master, $href, $stdOptions, $getAuthHeader, $header);
        }
		
        $running = false;
        do {
            //execute whichever handles need to be started
            do {
                $execrun = curl_multi_exec($master, $running);
            } while ($execrun == CURLM_CALL_MULTI_PERFORM);

            if ($execrun != CURLM_OK) {
                $crestExceptionClass = Config::getIveeClassName('IveeCrestException');
                throw new $crestExceptionClass("CURL Multi-GET error", $execrun);
            }

            //block until we have anything on at least one of the handles
            curl_multi_select($master);

            //a request returned, process it
            while ($done = curl_multi_info_read($master)) {
                //echo "curl_multi_info_read()...\n"; var_dump($done);
                $info = curl_getinfo($done['handle']);

                //find the Response object matching the URL
                $res = $responses[$info['url']];
                $url_short = str_replace(Config::getCrestBaseUrl(), '', $info['url']);

                //set info and content to Response object
                $res->setInfo($info);
                $res->setContent(curl_multi_getcontent($done['handle']));

                //execute the callbacks passing the response as argument
                if ($info['http_code'] == 200) {
                    #echo time2s()."got   ".$url_short."\n";
					$this->recordEvent();
					
                    //cache it if configured
                    if($cache)
                        $this->cache->setItem($res);
                    $callback($res);
                    if (isset($this->requeued[$info['url']])) {
                      $this->requeued[$info['url']] = NULL;
                      time2s().">>> recaptured ".$url_short."\n";
                    }

                } elseif (isset($errCallback)) {
                    #echo time2s()."cw.asyncMultiGet(): curl_multi, http ".$info['http_code']."\n";
                    #echo time2s()."requeueing ".$url_short."\n";
                    $errCallback($res);
                    $hrefsToQuery[] = $info['url']; //put back on queue
                    $this->requeued[$info['url']] = true;
                }
                //remove the reference to response to conserve memory on large batches
                $responses[$info['url']] = null;
                        
                //start a new request (it's important to do this before removing the old one)
                if ($i < count($hrefsToQuery)) {
                    $href = $hrefsToQuery[$i++];
                    //echo time2s()."curl.multi  $href\n";
                    $responses[$href] = $this->addHandleToMulti($master, $href, $stdOptions, $getAuthHeader, $header);
                }

                //remove the curl handle that just completed
                curl_multi_remove_handle($master, $done['handle']);
            }
            //don't waste too many CPU cycles on looping
            usleep(1000);
        } while ($running > 0);

        curl_multi_close($master);
     }

    /**
     * Creates new curl handle and adds to curl multi handle. Also creates the corresponding Response object.
     * 
     * @param curl_multi $multiHandle the CURL multi handle
     * @param string $href to be requested
     * @param array $stdOptions the CURL options to be set
     * @param callable $getAuthHeader that returns an appropriate bearer authentication header line, for instance 
     * Client::getBearerAuthHeader(). We do this on-the-fly as during large multi GET batches the access token might
     * expire.
     * @param array $header to be used in each request
     * 
     * @return \iveeCrest\Response
     */
    protected function addHandleToMulti($multiHandle, $href, array $stdOptions, callable $getAuthHeader, array $header)
    {
        $ch = curl_init();
        curl_setopt_array($ch, $stdOptions);
        curl_setopt($ch, CURLOPT_URL, $href);

        //add auth header on the fly
        curl_setopt($ch, CURLOPT_HTTPHEADER, array_merge($getAuthHeader(), $header));

        //instantiate new Response object
        $responseClass = Config::getIveeClassName('Response');
        $response = new $responseClass('get:' . $href);

        //add the CURL header callback function
        curl_setopt($ch, CURLOPT_HEADERFUNCTION, array($response, 'handleCurlHeaderLine'));
        curl_multi_add_handle($multiHandle, $ch);
        return $response;
    }
}
